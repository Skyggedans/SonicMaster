import 'package:flutter_midi_command/flutter_midi_command.dart';

import 'transport.dart';
import 'transport_packages.dart';

/// Web transports, backed by the Web MIDI (`flutter_midi_command`) and Web
/// Bluetooth (`universal_ble`) browser APIs.
Transport createTransport(TransportKind kind) => switch (kind) {
  .usb => MidiCommandTransport(),
  .ble => UniversalBleTransport(),
};

/// Web MIDI devices. The first call triggers the browser's MIDI/SysEx
/// permission prompt, so this must run from a user-activated context.
Future<List<UsbMidiDevice>> enumerateMidiDevices() async {
  final devices = await MidiCommand().devices ?? const [];

  return [
    for (final d in devices)
      UsbMidiDevice(
        d.name,
        hasInput: d.inputPorts.isNotEmpty,
        hasOutput: d.outputPorts.isNotEmpty,
      ),
  ];
}

/// Web Bluetooth has no passive scan — device selection happens through the
/// browser's own chooser on connect. Returns empty; the BLE connect path drives
/// the chooser directly.
Future<List<ScannedBle>> enumerateBleDevices() async => const [];
