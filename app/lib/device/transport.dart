import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';

/// Which transport the app uses to reach the pedal.
enum TransportKind { usb, ble }

/// No-op: the transports are the cross-platform packages (`flutter_midi_command`
/// / `universal_ble`), which initialize lazily on connect. Kept so `main` and
/// `DeviceService` can still call it unconditionally.
Future<void> initTransports() async {}

/// Whether a MIDI device matching [match] is currently enumerable — the liveness
/// signal USB lacks (it has no connection events). Returns true if present,
/// false if enumeration succeeded but the device is gone (unplugged / powered
/// off), and null if enumeration failed or timed out (unknown — the caller must
/// NOT treat this as a disconnect, to avoid false trips on a transient hiccup).
Future<bool?> usbInputPortPresent(String match) async {
  try {
    final needle = match.toLowerCase();

    final devices = await MidiCommand().devices.timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );

    if (devices == null) return null;

    return devices.any((d) => d.name.toLowerCase().contains(needle));
  } catch (_) {
    return null;
  }
}

/// A USB-MIDI device the app can open: a device with input and/or output ports.
/// The transport opens the same device for both directions, so only
/// [connectable] (both present) devices are pickable.
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

/// A BLE device seen by a scan, transport-agnostic (native or Web Bluetooth):
/// its advertised [name], [address]/id, and [rssi] (0 when unknown).
class ScannedBle {
  const ScannedBle({
    required this.name,
    required this.address,
    required this.rssi,
  });

  final String name;
  final String address;
  final int rssi;
}

/// The transport-specific surface `DeviceService` sits on: an F0-led inbound
/// packet stream, framing a stored `8080F0…F7` command onto the wire, and
/// connect/disconnect. Each impl also owns its own `TrafficLog` RX/TX taps.
abstract class Transport {
  /// Raw inbound SysEx packets, normalized to **F0-led** (both transports), for
  /// `classifyInbound`.
  Stream<Uint8List> rawPackets();

  /// Connect to the pedal ([target] overrides the transport's default — a USB
  /// device-name substring, or a BLE device name).
  Future<void> connect({String? target});

  /// Put a stored `8080F0…F7` command on the wire in this transport's framing.
  Future<void> sendFrame(String frameHex);

  Future<void> disconnect();

  /// Connection-state events (true=connected, false=disconnected), or null if
  /// the transport has none (MIDI).
  Stream<bool>? connectionEvents();
}
