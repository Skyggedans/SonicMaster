//! Thin MIDI transport over `midir`. No protocol knowledge — enumerate ports,
//! open a connection, send raw bytes, and stream received bytes. The Dart side
//! owns all SysEx logic.

use crate::frb_generated::StreamSink;
use std::sync::{Mutex, OnceLock};

/// Native library init hook (frb calls this on `RustLib.init()`).
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Direction of a MIDI port.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MidiDirection {
    Input,
    Output,
}

/// A MIDI port the host exposes, identified by its (platform) name.
#[derive(Debug, Clone)]
pub struct MidiPort {
    pub name: String,
    pub direction: MidiDirection,
}

/// Enumerate all input and output MIDI ports currently visible to the host.
pub fn list_ports() -> Result<Vec<MidiPort>, String> {
    let mut ports = Vec::new();

    let input = midir::MidiInput::new("sonicmaster-enum-in").map_err(|e| e.to_string())?;
    for port in input.ports() {
        let name = input.port_name(&port).map_err(|e| e.to_string())?;
        ports.push(MidiPort {
            name,
            direction: MidiDirection::Input,
        });
    }

    let output = midir::MidiOutput::new("sonicmaster-enum-out").map_err(|e| e.to_string())?;
    for port in output.ports() {
        let name = output.port_name(&port).map_err(|e| e.to_string())?;
        ports.push(MidiPort {
            name,
            direction: MidiDirection::Output,
        });
    }

    Ok(ports)
}

// ---- Session event stream + connection ----

/// The long-lived inbound event stream to Dart, registered ONCE per session
/// (via `midi_events`) and never per-connection — so opening/closing a device
/// never clobbers it and there is no setup race.
static EVENTS: OnceLock<Mutex<Option<StreamSink<Vec<u8>>>>> = OnceLock::new();
/// The live connection, kept alive so its input callback keeps firing.
static CONNECTION: OnceLock<Mutex<Option<Connection>>> = OnceLock::new();

fn events_slot() -> &'static Mutex<Option<StreamSink<Vec<u8>>>> {
    EVENTS.get_or_init(|| Mutex::new(None))
}

fn connection_slot() -> &'static Mutex<Option<Connection>> {
    CONNECTION.get_or_init(|| Mutex::new(None))
}

/// Locks recovering from poisoning — hardware I/O must not brick on a panic.
fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

struct Connection {
    _input: midir::MidiInputConnection<()>,
    output: midir::MidiOutputConnection,
}

fn port_matches(port_name: &str, wanted: &str) -> bool {
    port_name == wanted || port_name.contains(wanted)
}

/// The session's inbound MIDI event stream: every received message, across all
/// connect/reconnect cycles, arrives here. On the Dart side this is a
/// `Stream<Uint8List>`. Call ONCE at startup and keep the subscription for the
/// app's lifetime; calling again replaces (and closes) the previous stream.
pub fn midi_events(sink: StreamSink<Vec<u8>>) {
    *lock(events_slot()) = Some(sink);
}

/// Opens the input+output ports whose names contain the given strings and
/// forwards received messages to the session event stream. Awaitable: it
/// completes only once both ports are open, so a subsequent `send_bytes` is
/// safe. State is mutated only after both ports open, so a failed open (e.g.
/// port not found) leaves any existing connection untouched.
pub fn open_connection(input_name: String, output_name: String) -> Result<(), String> {
    let midi_out = midir::MidiOutput::new("sonicmaster-out").map_err(|e| e.to_string())?;
    let out_port = midi_out
        .ports()
        .into_iter()
        .find(|p| port_matches(&midi_out.port_name(p).unwrap_or_default(), &output_name))
        .ok_or_else(|| format!("output MIDI port not found: {output_name}"))?;
    let output = midi_out
        .connect(&out_port, "sonicmaster")
        .map_err(|e| e.to_string())?;

    let midi_in = midir::MidiInput::new("sonicmaster-in").map_err(|e| e.to_string())?;
    let in_port = midi_in
        .ports()
        .into_iter()
        .find(|p| port_matches(&midi_in.port_name(p).unwrap_or_default(), &input_name))
        .ok_or_else(|| format!("input MIDI port not found: {input_name}"))?;
    let input = midi_in
        .connect(
            &in_port,
            "sonicmaster",
            |_ts, msg, _| {
                let bytes = msg.to_vec(); // allocate off the lock (hot RX path)
                if let Some(sink) = lock(events_slot()).as_ref() {
                    let _ = sink.add(bytes);
                }
            },
            (),
        )
        .map_err(|e| e.to_string())?;

    *lock(connection_slot()) = Some(Connection {
        _input: input,
        output,
    });
    Ok(())
}

/// Sends raw bytes to the open output connection.
pub fn send_bytes(bytes: Vec<u8>) -> Result<(), String> {
    let mut guard = lock(connection_slot());
    let conn = guard.as_mut().ok_or("no open MIDI connection")?;
    conn.output.send(&bytes).map_err(|e| e.to_string())
}

/// Closes the current device connection (drops input+output). The session event
/// stream from `midi_events` stays open — "connected" is separate state.
pub fn close_connection() {
    *lock(connection_slot()) = None;
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

    #[test]
    fn list_ports_returns_visible_ports() {
        let ports = list_ports().expect("list_ports failed");
        for p in &ports {
            println!("PORT: {:?}\t{}", p.direction, p.name);
        }
        // Any Linux with ALSA exposes at least "Midi Through"; a connected
        // device adds more. Never expect zero on a real host.
        assert!(!ports.is_empty(), "expected at least one MIDI port");
    }

    /// Hardware round-trip: send a read-only global-settings query to the pedal
    /// and confirm it replies. Requires the Sonicake pedal connected.
    /// Run with: `cargo test --lib -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn round_trip_query_global_settings() {
        use midir::{MidiInput, MidiOutput};
        use std::sync::{Arc, Mutex};
        use std::time::Duration;

        const TARGET: &str = "Smart Box";
        // Request global settings (8080F00B0900010000000201020100F7); over USB
        // MIDI the leading 8080 BLE header is stripped, so we send f0..f7.
        let request = hex_to_bytes("F00B0900010000000201020100F7");

        let midi_out = MidiOutput::new("pe-test-out").unwrap();
        let out_port = midi_out
            .ports()
            .into_iter()
            .find(|p| midi_out.port_name(p).unwrap().contains(TARGET))
            .expect("no 'Smart Box' output port — is the pedal connected?");
        let mut conn_out = midi_out.connect(&out_port, "pe-out").unwrap();

        let received = Arc::new(Mutex::new(Vec::<Vec<u8>>::new()));
        let sink = received.clone();
        let midi_in = MidiInput::new("pe-test-in").unwrap();
        let in_port = midi_in
            .ports()
            .into_iter()
            .find(|p| midi_in.port_name(p).unwrap().contains(TARGET))
            .expect("no 'Smart Box' input port");
        let _conn_in = midi_in
            .connect(
                &in_port,
                "pe-in",
                move |_ts, msg, _| sink.lock().unwrap().push(msg.to_vec()),
                (),
            )
            .unwrap();

        conn_out.send(&request).unwrap();
        std::thread::sleep(Duration::from_millis(700));

        let got = received.lock().unwrap();
        for m in got.iter() {
            let hex: String = m.iter().map(|b| format!("{:02X}", b)).collect();
            println!("RECV {} bytes: {}", m.len(), hex);
        }
        assert!(!got.is_empty(), "pedal sent no response to the query");
    }
}
