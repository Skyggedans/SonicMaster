import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:universal_ble/universal_ble.dart';

import 'ble_framing.dart';
import 'midi_framing.dart';
import 'traffic_log.dart';
import 'transport.dart';

/// The BLE-MIDI GATT identifiers the pedal advertises — identical to the ones
/// the (removed) native `flutter_btleplug` plugin hard-coded.
const bleMidiServiceUuid = '03b80e5a-ede8-4b33-a751-6ce34ec4c700';
const bleMidiCharUuid = '7772e5db-3868-4112-a1a9-f2669d106bf3';

/// Default device-name substrings used when the caller passes no explicit
/// target — mirrors the earlier `UsbTransport`/`BleTransport` defaults.
const _defaultUsbTarget = 'Smart Box';
const _defaultBleTarget = 'Smart Box BLE';

/// USB-MIDI transport backed by `flutter_midi_command` — native CoreMIDI/ALSA/
/// win32 on desktop, the browser Web MIDI API (with SysEx) on web. Slots into
/// the [Transport] seam; inbound SysEx is already F0-led.
class MidiCommandTransport implements Transport {
  MidiCommandTransport() {
    _attachRx();
  }

  final MidiCommand _midi = MidiCommand();
  final StreamController<Uint8List> _rx =
      StreamController<Uint8List>.broadcast();

  StreamSubscription<dynamic>? _rxSub;
  MidiDevice? _device;

  /// (Re)subscribes to the merged inbound packet stream. On web the stream only
  /// materializes once Web MIDI access is granted, so this is called again from
  /// [connect] after enumeration.
  void _attachRx() {
    _rxSub?.cancel();

    final packets = _midi.onMidiPacketReceived;

    if (packets == null) return;

    _rxSub = packets.listen((p) => _rx.add(p.data));
  }

  @override
  Stream<Uint8List> rawPackets() => _rx.stream.map((p) {
    TrafficLog.record('RX', p);

    return p;
  });

  @override
  Future<void> connect({String? target}) async {
    final needle = (target ?? _defaultUsbTarget).toLowerCase();

    // Enumerating devices triggers the browser's Web MIDI (SysEx) permission
    // prompt on web — this must be reached from a user gesture there.
    final devices = await _midi.devices ?? <MidiDevice>[];

    final matches = devices.where((d) => d.name.toLowerCase().contains(needle));

    if (matches.isEmpty) {
      throw StateError('No MIDI device matching "$target"');
    }

    final match = matches.first;

    await _midi.connectToDevice(match);

    _device = match;

    // The receive stream becomes available once access is granted.
    _attachRx();
  }

  @override
  Future<void> sendFrame(String frameHex) async {
    final wire = MidiFraming.toWire(frameHex); // strips the 8080 header

    TrafficLog.record('TX', wire);

    _midi.sendData(wire, deviceId: _device?.id);
  }

  @override
  Future<void> disconnect() async {
    final device = _device;

    if (device != null) {
      _midi.disconnectDevice(device);
    }

    _device = null;
  }

  @override
  Stream<bool>? connectionEvents() => null; // no link-state events for MIDI
}

/// BLE transport backed by `universal_ble` — native BlueZ/WinRT/CoreBluetooth on
/// desktop, the browser Web Bluetooth GATT API on web. Slots into the
/// [Transport] seam; keeps the 8080-led wire and strips to F0-led on the way in.
class UniversalBleTransport implements Transport {
  final StreamController<Uint8List> _rx =
      StreamController<Uint8List>.broadcast();
  final StreamController<bool> _conn = StreamController<bool>.broadcast();

  StreamSubscription<Uint8List>? _valueSub;
  StreamSubscription<bool>? _connSub;
  String? _deviceId;

  @override
  Stream<Uint8List> rawPackets() => _rx.stream.map((n) {
    TrafficLog.record('RX', n); // the real 8080-led wire

    return BleFraming.toF0Led(n); // strip to F0-led for classifyInbound
  });

  @override
  Future<void> connect({String? target}) async {
    final needle = (target ?? _defaultBleTarget).toLowerCase();

    final device = await _scanForDevice(needle);

    if (device == null) {
      throw StateError('No BLE device matching "$target"');
    }

    final id = device.deviceId;

    await UniversalBle.connect(id);
    await UniversalBle.discoverServices(id);
    await UniversalBle.subscribeNotifications(
      id,
      bleMidiServiceUuid,
      bleMidiCharUuid,
    );

    _valueSub?.cancel();
    _valueSub = UniversalBle.characteristicValueStream(
      id,
      bleMidiCharUuid,
    ).listen(_rx.add);

    _connSub?.cancel();
    _connSub = UniversalBle.connectionStream(id).listen(_conn.add);

    _deviceId = id;
  }

  /// Scans (filtered to the BLE-MIDI service) until a device whose advertised
  /// name contains [needle] appears, or a 10s timeout elapses. On web the scan
  /// surfaces the browser's own device chooser and requires a user gesture.
  Future<BleDevice?> _scanForDevice(String needle) async {
    final completer = Completer<BleDevice?>();

    final sub = UniversalBle.scanStream.listen((d) {
      // On web, universal_ble's scan is `requestDevice` — the browser chooser
      // already returned the user's single chosen device, so take it regardless
      // of name. On native, match the picked name against the passive scan.
      final isMatch = kIsWeb || (d.name?.toLowerCase() ?? '').contains(needle);

      if (isMatch && !completer.isCompleted) {
        completer.complete(d);
      }
    });

    await UniversalBle.startScan(
      scanFilter: ScanFilter(withServices: const [bleMidiServiceUuid]),
    );

    final device = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );

    await sub.cancel();
    await UniversalBle.stopScan();

    return device;
  }

  @override
  Future<void> sendFrame(String frameHex) async {
    final id = _deviceId;

    if (id == null) return;

    final wire = BleFraming.toWire(frameHex); // verbatim, keeps 8080

    TrafficLog.record('TX', wire);

    await UniversalBle.write(
      id,
      bleMidiServiceUuid,
      bleMidiCharUuid,
      wire,
      withoutResponse: true,
    );
  }

  @override
  Future<void> disconnect() async {
    final id = _deviceId;

    await _valueSub?.cancel();
    _valueSub = null;

    await _connSub?.cancel();
    _connSub = null;

    if (id != null) {
      await UniversalBle.disconnect(id);
    }

    _deviceId = null;
  }

  @override
  Stream<bool>? connectionEvents() => _conn.stream;
}
