/// A thin, reusable MIDI transport plugin backed by the Rust `midir` crate.
///
/// The plugin knows nothing about any device protocol — it enumerates ports,
/// opens one input+output connection, sends raw bytes, and exposes a session
/// stream of received bytes. All SysEx/CRC/framing logic lives in the app.
library;

import 'dart:typed_data';

import 'src/rust/api/midi.dart' as rust;
import 'src/rust/frb_generated.dart';

export 'src/rust/api/midi.dart' show MidiPort, MidiDirection;

/// Loads the native library. Call once at startup before any other call.
Future<void> initMidi() => RustLib.init();

/// Enumerate all input and output MIDI ports currently visible to the host.
Future<List<rust.MidiPort>> listMidiPorts() => rust.listPorts();

/// The session's inbound MIDI event stream: every received message (each event
/// is one message's raw bytes, e.g. a bare `F0 … F7` over USB MIDI), across all
/// connect/reconnect cycles.
///
/// Listen **once** at startup and keep the subscription for the app's lifetime;
/// calling this again replaces (and closes) the previous stream. Because the
/// stream is session-scoped, it is registered independently of any connection,
/// so opening/closing a device never disturbs it and there is no setup race.
Stream<Uint8List> midiEvents() => rust.midiEvents();

/// Opens the device whose input/output port names contain [inputPortName] /
/// [outputPortName] (substring match). Completes once both ports are open — so
/// a subsequent [sendMidi] is safe — and throws if a matching port is not
/// found. Replaces any existing connection; a failed open leaves the previous
/// connection untouched.
Future<void> openMidiConnection({
  required String inputPortName,
  required String outputPortName,
}) => rust.openConnection(inputName: inputPortName, outputName: outputPortName);

/// Sends raw bytes to the open device. The caller supplies exactly what should
/// go on the wire (over USB MIDI a bare `F0 … F7`, with no `8080` header).
Future<void> sendMidi(Uint8List bytes) => rust.sendBytes(bytes: bytes);

/// Closes the current device connection. The [midiEvents] stream stays open —
/// "connected" is separate state the app tracks itself.
Future<void> closeMidiConnection() => rust.closeConnection();
