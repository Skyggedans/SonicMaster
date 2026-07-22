//! Thin BLE-MIDI transport over `btleplug`. No protocol knowledge — scan,
//! connect to a device by advertised name, subscribe to the BLE-MIDI
//! characteristic's notifications, and write raw bytes. The Dart side owns all
//! SysEx / BLE-MIDI framing logic.

use crate::frb_generated::StreamSink;
use btleplug::api::{
    Central, CentralEvent, Manager as _, Peripheral as _, ScanFilter, WriteType,
};
use btleplug::platform::{Manager, Peripheral};
use futures::StreamExt;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;
use uuid::Uuid;

/// Standard BLE-MIDI service + data I/O characteristic (MMA spec).
const MIDI_SERVICE: Uuid = Uuid::from_u128(0x03b80e5a_ede8_4b33_a751_6ce34ec4c700);
const MIDI_CHAR: Uuid = Uuid::from_u128(0x7772e5db_3868_4112_a1a9_f2669d106bf3);

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// A BLE device seen while scanning.
#[derive(Debug, Clone)]
pub struct BleDevice {
    pub name: String,
    pub address: String,
    pub rssi: i32,
}

static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
static EVENTS: OnceLock<Mutex<Option<StreamSink<Vec<u8>>>>> = OnceLock::new();
static DEVICE: OnceLock<Mutex<Option<Peripheral>>> = OnceLock::new();
/// The notification-forwarding task for the current connection, so it can be
/// aborted when the connection is replaced or dropped (btleplug does not end
/// the stream or disconnect on drop of the `Peripheral` handle).
static FORWARDER: OnceLock<Mutex<Option<tokio::task::JoinHandle<()>>>> = OnceLock::new();
/// Session connection-state stream (true=connected, false=disconnected).
static CONN_EVENTS: OnceLock<Mutex<Option<StreamSink<bool>>>> = OnceLock::new();
/// The central-event monitor task that detects this connection's disconnect.
static MONITOR: OnceLock<Mutex<Option<tokio::task::JoinHandle<()>>>> = OnceLock::new();

fn rt() -> &'static tokio::runtime::Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("tokio runtime")
    })
}
fn events_slot() -> &'static Mutex<Option<StreamSink<Vec<u8>>>> {
    EVENTS.get_or_init(|| Mutex::new(None))
}
fn device_slot() -> &'static Mutex<Option<Peripheral>> {
    DEVICE.get_or_init(|| Mutex::new(None))
}
fn forwarder_slot() -> &'static Mutex<Option<tokio::task::JoinHandle<()>>> {
    FORWARDER.get_or_init(|| Mutex::new(None))
}
fn conn_slot() -> &'static Mutex<Option<StreamSink<bool>>> {
    CONN_EVENTS.get_or_init(|| Mutex::new(None))
}
fn monitor_slot() -> &'static Mutex<Option<tokio::task::JoinHandle<()>>> {
    MONITOR.get_or_init(|| Mutex::new(None))
}
/// Aborts the forwarder + disconnect-monitor tasks and disconnects the current
/// device, if any. Takes each out of its slot first (dropping the guard) so no
/// lock is held across the disconnect await.
async fn teardown_current() {
    if let Some(h) = lock(forwarder_slot()).take() {
        h.abort();
    }
    if let Some(h) = lock(monitor_slot()).take() {
        h.abort();
    }
    let old = lock(device_slot()).take();
    if let Some(p) = old {
        let _ = p.disconnect().await;
    }
}
fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

async fn central() -> Result<btleplug::platform::Adapter, String> {
    let manager = Manager::new().await.map_err(|e| e.to_string())?;
    manager
        .adapters()
        .await
        .map_err(|e| e.to_string())?
        .into_iter()
        .next()
        .ok_or_else(|| "no BLE adapter".to_string())
}

/// The session inbound stream: every notification payload, across connect
/// cycles, arrives here as a `Stream<Uint8List>`. Call ONCE at startup.
pub fn ble_events(sink: StreamSink<Vec<u8>>) {
    *lock(events_slot()) = Some(sink);
}

/// The session connection-state stream: `true` after a connect, `false` when the
/// connected device disconnects (drop or explicit). The app decides policy
/// (e.g. auto-reconnect on an unexpected drop). Call ONCE at startup.
pub fn connection_events(sink: StreamSink<bool>) {
    *lock(conn_slot()) = Some(sink);
}

/// Scan for [timeout_ms] and return the visible BLE devices (named ones first).
pub fn scan(timeout_ms: u64) -> Result<Vec<BleDevice>, String> {
    rt().block_on(async {
        let central = central().await?;
        central
            .start_scan(ScanFilter::default())
            .await
            .map_err(|e| e.to_string())?;
        tokio::time::sleep(Duration::from_millis(timeout_ms)).await;
        let mut out = Vec::new();
        for p in central.peripherals().await.map_err(|e| e.to_string())? {
            let props = match p.properties().await.map_err(|e| e.to_string())? {
                Some(x) => x,
                None => continue,
            };
            out.push(BleDevice {
                name: props.local_name.unwrap_or_default(),
                address: p.address().to_string(),
                rssi: props.rssi.unwrap_or(0) as i32,
            });
        }
        let _ = central.stop_scan().await;
        // Named devices first (false < true, so non-empty names sort ahead).
        out.sort_by(|a, b| a.name.is_empty().cmp(&b.name.is_empty()));
        Ok(out)
    })
}

/// Scan, connect to the device whose advertised name matches [name] (exact
/// preferred, else substring), subscribe to the BLE-MIDI characteristic, and
/// forward its notifications to the session event stream. Awaitable: returns
/// only once subscribed, so a subsequent `send_bytes` is safe.
pub fn connect(name: String, scan_ms: u64) -> Result<(), String> {
    rt().block_on(async {
        let central = central().await?;
        central
            .start_scan(ScanFilter::default())
            .await
            .map_err(|e| e.to_string())?;
        tokio::time::sleep(Duration::from_millis(scan_ms)).await;
        let peripherals = central.peripherals().await.map_err(|e| e.to_string())?;
        let _ = central.stop_scan().await;

        let mut found: Option<Peripheral> = None;
        let mut fallback: Option<Peripheral> = None;
        for p in peripherals {
            let n = p
                .properties()
                .await
                .ok()
                .flatten()
                .and_then(|x| x.local_name)
                .unwrap_or_default();
            if n == name {
                found = Some(p);
                break;
            }
            if !name.is_empty() && n.contains(&name) && fallback.is_none() {
                fallback = Some(p);
            }
        }
        let p = found
            .or(fallback)
            .ok_or_else(|| format!("BLE device not found: {name}"))?;

        p.connect().await.map_err(|e| e.to_string())?;
        p.discover_services().await.map_err(|e| e.to_string())?;
        let chr = p
            .characteristics()
            .into_iter()
            .find(|c| c.uuid == MIDI_CHAR && c.service_uuid == MIDI_SERVICE)
            .ok_or_else(|| "BLE-MIDI characteristic not found".to_string())?;
        p.subscribe(&chr).await.map_err(|e| e.to_string())?;
        let mut stream = p.notifications().await.map_err(|e| e.to_string())?;
        // Central event stream + device id, to detect a disconnect (the
        // notification stream does NOT end on disconnect under BlueZ).
        let mut events = central.events().await.map_err(|e| e.to_string())?;
        let dev_id = p.id();

        // The new connection is fully established; only now retire the previous
        // one (so a failed connect above left it untouched). btleplug does not
        // auto-disconnect or end the old stream on drop, so do both explicitly.
        teardown_current().await;

        let handle = rt().spawn(async move {
            while let Some(n) = stream.next().await {
                if let Some(sink) = lock(events_slot()).as_ref() {
                    let _ = sink.add(n.value);
                }
            }
        });
        let mon = rt().spawn(async move {
            while let Some(ev) = events.next().await {
                if let CentralEvent::DeviceDisconnected(id) = ev {
                    if id == dev_id {
                        if let Some(sink) = lock(conn_slot()).as_ref() {
                            let _ = sink.add(false);
                        }
                        break;
                    }
                }
            }
        });
        *lock(forwarder_slot()) = Some(handle);
        *lock(monitor_slot()) = Some(mon);
        *lock(device_slot()) = Some(p);
        if let Some(sink) = lock(conn_slot()).as_ref() {
            let _ = sink.add(true);
        }
        Ok(())
    })
}

/// Write raw bytes to the BLE-MIDI characteristic (write-without-response).
pub fn send_bytes(bytes: Vec<u8>) -> Result<(), String> {
    rt().block_on(async {
        // Clone the handle out and drop the guard so the lock is not held across
        // the write await (a stuck write must not block a concurrent disconnect).
        let p = lock(device_slot())
            .as_ref()
            .cloned()
            .ok_or("no BLE connection")?;
        let chr = p
            .characteristics()
            .into_iter()
            .find(|c| c.uuid == MIDI_CHAR && c.service_uuid == MIDI_SERVICE)
            .ok_or("BLE-MIDI characteristic missing")?;
        p.write(&chr, &bytes, WriteType::WithoutResponse)
            .await
            .map_err(|e| e.to_string())
    })
}

/// Disconnect the current device (and stop its forwarder). The session event
/// stream stays open.
pub fn disconnect() {
    rt().block_on(teardown_current());
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex_to_bytes(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    /// Live BLE round-trip against the pedal. Verifies the module's `scan`
    /// wrapper finds `Smart Box BLE`, then (via btleplug directly, since the
    /// notification path forwards to a Dart StreamSink) connects, writes the
    /// state request, and confirms a reply frame comes back.
    /// Run: `cargo test --lib -- --ignored --nocapture round_trip`
    #[test]
    #[ignore]
    fn round_trip_state_request_over_ble() {
        const NAME: &str = "Smart Box BLE";

        // 1. The module's own scan wrapper sees the pedal.
        let devices = scan(4000).expect("scan failed");
        for d in &devices {
            println!("BLE {} {:?} rssi={}", d.address, d.name, d.rssi);
        }
        assert!(
            devices.iter().any(|d| d.name == NAME),
            "pedal '{NAME}' not advertising BLE"
        );

        // 2. Connect + round-trip via btleplug directly (the StreamSink path is
        //    Dart-only and verified in the app integration).
        rt().block_on(async {
            let central = central().await.unwrap();
            central.start_scan(ScanFilter::default()).await.unwrap();
            tokio::time::sleep(Duration::from_millis(4000)).await;
            let mut target = None;
            for p in central.peripherals().await.unwrap() {
                let n = p
                    .properties()
                    .await
                    .ok()
                    .flatten()
                    .and_then(|x| x.local_name)
                    .unwrap_or_default();
                if n == NAME {
                    target = Some(p);
                    break;
                }
            }
            let _ = central.stop_scan().await;
            let p = target.expect("pedal not found on second scan");
            p.connect().await.unwrap();
            p.discover_services().await.unwrap();
            let chr = p
                .characteristics()
                .into_iter()
                .find(|c| c.uuid == MIDI_CHAR)
                .expect("no BLE-MIDI characteristic");
            p.subscribe(&chr).await.unwrap();
            let mut notifs = p.notifications().await.unwrap();

            p.write(
                &chr,
                &hex_to_bytes("8080F0000900010000000201020401F7"),
                WriteType::WithoutResponse,
            )
            .await
            .unwrap();

            let mut frames = 0;
            let _ = tokio::time::timeout(Duration::from_millis(2000), async {
                while let Some(n) = notifs.next().await {
                    let hex: String =
                        n.value.iter().map(|b| format!("{b:02X}")).collect();
                    println!("RECV {} bytes: {hex}", n.value.len());
                    frames += 1;
                    if frames >= 5 {
                        break;
                    }
                }
            })
            .await;
            p.disconnect().await.unwrap();
            assert!(frames > 0, "pedal sent no BLE response frames");
        });
    }
}
