import 'dart:typed_data';

import 'package:flutter_btleplug/flutter_btleplug.dart' as ble;
import 'package:flutter_midir/flutter_midir.dart' as usb;

import 'ble_framing.dart';
import 'midi_framing.dart';
import 'traffic_log.dart';

/// Which transport the app uses to reach the pedal.
enum TransportKind { usb, ble }

// The native event getters (`midiEvents`/`bleEvents`) are documented call-once —
// each overwrites the plugin's single event-sink slot. Invoke each exactly once
// and memoize as a broadcast stream so successive `Transport` instances (rebuilt
// on every transport switch) reuse it instead of re-registering the sink.
bool _inited = false;
Stream<Uint8List>? _usbEvents;
Stream<Uint8List>? _bleEvents;
Stream<bool>? _bleConnEvents;

/// Loads both native plugin libraries and memoizes their event streams. Call
/// once at startup; idempotent (repeat calls are a no-op).
Future<void> initTransports() async {
  if (_inited) return;

  _inited = true;
  await usb.initMidi();
  await ble.initBle();
  _usbEvents = usb.midiEvents().asBroadcastStream();
  _bleEvents = ble.bleEvents().asBroadcastStream();
  _bleConnEvents = ble.connectionEvents().asBroadcastStream();
}

/// The real platform name of the connected USB MIDI input port — the first
/// input port whose name contains [match] (the substring used to open it), or
/// null if none is visible or port enumeration is unavailable.
Future<String?> usbInputPortName(String match) async {
  try {
    final needle = match.toLowerCase();

    for (final p in await usb.listMidiPorts()) {
      if (p.direction == .input && p.name.toLowerCase().contains(needle)) {
        return p.name;
      }
    }
  } catch (_) {
    // enumeration unavailable — caller falls back to the match string
  }

  return null;
}

/// Whether a USB-MIDI input port matching [match] is currently enumerable —
/// the liveness signal USB lacks (it has no connection events). Returns true if
/// present, false if enumeration succeeded but the port is gone (device
/// unplugged / powered off), and null if enumeration itself failed (unknown —
/// the caller must NOT treat this as a disconnect, to avoid false trips on a
/// transient enumeration hiccup).
Future<bool?> usbInputPortPresent(String match) async {
  try {
    final needle = match.toLowerCase();
    final ports = await usb.listMidiPorts();

    return ports.any(
      (p) => p.direction == .input && p.name.toLowerCase().contains(needle),
    );
  } catch (_) {
    return null;
  }
}

/// A USB-MIDI device the app can open: a device name present on an input
/// and/or output port. [UsbTransport.connect] opens the same name for both
/// directions, so only [connectable] (both present) devices are pickable.
class UsbMidiDevice {
  const UsbMidiDevice(
    this.name, {
    required this.hasInput,
    required this.hasOutput,
  });

  final String name;
  final bool hasInput;
  final bool hasOutput;

  bool get connectable => hasInput && hasOutput;
}

/// Enumerates USB-MIDI devices by grouping the input/output ports that share a
/// name. Connectable devices (both directions) sort first. Empty if enumeration
/// is unavailable.
Future<List<UsbMidiDevice>> scanUsbMidi() async {
  final byName = <String, List<bool>>{}; // name -> [hasInput, hasOutput]

  try {
    for (final p in await usb.listMidiPorts()) {
      final e = byName.putIfAbsent(p.name, () => [false, false]);

      if (p.direction == .input) e[0] = true;

      if (p.direction == .output) e[1] = true;
    }
  } catch (_) {
    // enumeration unavailable
  }

  final list = [
    for (final e in byName.entries)
      UsbMidiDevice(e.key, hasInput: e.value[0], hasOutput: e.value[1]),
  ];

  list.sort((a, b) {
    if (a.connectable != b.connectable) return a.connectable ? -1 : 1;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return list;
}

/// The transport-specific surface `DeviceService` sits on: an F0-led inbound
/// packet stream, framing a stored `8080F0…F7` command onto the wire, and
/// connect/disconnect. Each impl also owns its own [TrafficLog] RX/TX taps.
abstract class Transport {
  /// Raw inbound SysEx packets, normalized to **F0-led** (both transports), for
  /// `classifyInbound`.
  Stream<Uint8List> rawPackets();

  /// Connect to the pedal ([target] overrides the transport's default — a USB
  /// port substring, or a BLE device name).
  Future<void> connect({String? target});

  /// Put a stored `8080F0…F7` command on the wire in this transport's framing.
  Future<void> sendFrame(String frameHex);

  Future<void> disconnect();

  /// Connection-state events (true=connected, false=disconnected), or null if
  /// the transport has none (USB).
  Stream<bool>? connectionEvents();
}

class UsbTransport implements Transport {
  @override
  Stream<Uint8List> rawPackets() => _usbEvents!.map((p) {
    TrafficLog.record('RX', p);

    return p;
  });

  @override
  Future<void> connect({String? target}) {
    final t = target ?? 'Smart Box';

    return usb.openMidiConnection(inputPortName: t, outputPortName: t);
  }

  @override
  Future<void> sendFrame(String frameHex) {
    final wire = MidiFraming.toWire(frameHex); // strips the 8080 header

    TrafficLog.record('TX', wire);

    return usb.sendMidi(wire);
  }

  @override
  Future<void> disconnect() => usb.closeMidiConnection();

  @override
  Stream<bool>? connectionEvents() => null; // USB has no connection events
}

class BleTransport implements Transport {
  @override
  Stream<Uint8List> rawPackets() => _bleEvents!.map((n) {
    TrafficLog.record('RX', n); // the real 8080-led wire

    return BleFraming.toF0Led(n); // strip to F0-led for classifyInbound
  });

  @override
  Future<void> connect({String? target}) =>
      ble.connectBle(name: target ?? 'Smart Box BLE');

  @override
  Future<void> sendFrame(String frameHex) {
    final wire = BleFraming.toWire(frameHex); // verbatim, keeps 8080

    TrafficLog.record('TX', wire);

    return ble.sendBle(wire);
  }

  @override
  Future<void> disconnect() => ble.disconnectBle();

  @override
  Stream<bool>? connectionEvents() => _bleConnEvents;
}
