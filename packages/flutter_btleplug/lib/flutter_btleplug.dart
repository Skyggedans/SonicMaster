/// A thin, reusable BLE-MIDI transport plugin backed by the Rust `btleplug`
/// crate.
///
/// The plugin knows nothing about any device protocol — it scans, connects to a
/// device by advertised name, subscribes to the standard BLE-MIDI
/// characteristic, sends raw bytes, and exposes a session stream of received
/// bytes. All SysEx/CRC/framing logic lives in the app. (Over BLE-MIDI each
/// notification is already a complete `8080 F0 … F7` frame — unlike USB MIDI,
/// nothing is stripped or prepended.)
library;

import 'dart:typed_data';

import 'src/rust/api/ble.dart' as rust;
import 'src/rust/frb_generated.dart';

export 'src/rust/api/ble.dart' show BleDevice;

/// Loads the native library. Call once at startup before any other call.
Future<void> initBle() => RustLib.init();

/// The session's inbound stream: every received notification payload (each a
/// complete BLE-MIDI `8080 F0 … F7` frame), across all connect/reconnect cycles.
///
/// Listen **once** at startup and keep the subscription for the app's lifetime;
/// calling this again replaces (and closes) the previous stream. It is
/// registered independently of any connection, so connecting/disconnecting a
/// device never disturbs it and there is no setup race.
Stream<Uint8List> bleEvents() => rust.bleEvents();

/// The session connection-state stream: `true` after a connect, `false` when
/// the connected device disconnects (drop or explicit). Listen once at startup;
/// the app decides policy (e.g. auto-reconnect on an unexpected drop).
Stream<bool> connectionEvents() => rust.connectionEvents();

/// Scan for [timeout] and return the visible BLE devices (named devices first).
Future<List<rust.BleDevice>> scanBle({
  Duration timeout = const Duration(seconds: 4),
}) => rust.scan(timeoutMs: BigInt.from(timeout.inMilliseconds));

/// Scans, then connects to the device whose advertised name matches [name]
/// (exact preferred, else substring), subscribing to its BLE-MIDI
/// characteristic. Completes once subscribed — so a subsequent [sendBle] is
/// safe — and throws if no matching device is found. A failed connect leaves
/// any previous connection untouched.
Future<void> connectBle({
  required String name,
  Duration scanTime = const Duration(seconds: 4),
}) => rust.connect(name: name, scanMs: BigInt.from(scanTime.inMilliseconds));

/// Sends raw bytes to the connected device (write-without-response). The caller
/// supplies exactly what should go on the wire (over BLE-MIDI the full
/// `8080 F0 … F7` frame, header included).
Future<void> sendBle(Uint8List bytes) => rust.sendBytes(bytes: bytes);

/// Disconnects the current device. The [bleEvents] stream stays open —
/// "connected" is separate state the app tracks itself.
Future<void> disconnectBle() => rust.disconnect();
