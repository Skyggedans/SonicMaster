import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:universal_ble/universal_ble.dart';

import 'transport.dart';
import 'transport_packages.dart';

/// Desktop transports — the same cross-platform packages as web
/// (`flutter_midi_command` over ALSA/CoreMIDI/win32, `universal_ble` over
/// BlueZ/WinRT/CoreBluetooth).
Transport createTransport(TransportKind kind) => switch (kind) {
  .usb => MidiCommandTransport(),
  .ble => UniversalBleTransport(),
};

/// USB-MIDI devices from the OS MIDI stack.
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

/// BLE-MIDI devices from a native scan (filtered to the MIDI service), collected
/// over a short window and sorted by signal strength.
Future<List<ScannedBle>> enumerateBleDevices() async {
  final found = <String, ScannedBle>{};

  final sub = UniversalBle.scanStream.listen((d) {
    found[d.deviceId] = ScannedBle(
      name: d.name ?? '',
      address: d.deviceId,
      rssi: d.rssi ?? 0,
    );
  });

  await UniversalBle.startScan(
    scanFilter: ScanFilter(withServices: const [bleMidiServiceUuid]),
  );

  await Future<void>.delayed(const Duration(seconds: 3));

  await sub.cancel();
  await UniversalBle.stopScan();

  final list = found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

  return list;
}
