import 'package:flutter_midir/flutter_midir.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_model.dart';
import '../device/device_service.dart';
import '../device/transport.dart';
import '../protocol/inbound_message.dart';

/// Which transport the app talks to the pedal over.
final transportKindProvider = StateProvider<TransportKind>((ref) => .usb);

/// The app's single [DeviceService], rebuilt when the transport changes. Native
/// libs are loaded once at startup (`initTransports`), so listening is sync.
final deviceServiceProvider = Provider<DeviceService>((ref) {
  final kind = ref.watch(transportKindProvider);
  final transport = switch (kind) {
    .usb => UsbTransport(),
    .ble => BleTransport(),
  };

  final service = DeviceService(transport)..startListening();

  ref.onDispose(service.dispose);

  return service;
});

/// Available USB MIDI ports (dev tooling).
final midiPortsProvider = FutureProvider<List<MidiPort>>(
  (ref) => listMidiPorts(),
);

/// Classified inbound messages from the device.
final inboundProvider = StreamProvider<InboundMessage>(
  (ref) => ref.watch(deviceServiceProvider).inbound,
);

/// Whether a device connection is currently open (set by the UI on connect).
final connectionStateProvider = StateProvider<bool>((ref) => false);

/// The last BLE device name connected to (for auto-reconnect on a drop).
final lastBleTargetProvider = StateProvider<String?>((ref) => null);

/// The real name of the currently connected device — the BLE advertised name or
/// the USB MIDI port name — shown in the status. Null when disconnected.
final connectedDeviceNameProvider = StateProvider<String?>((ref) => null);

/// The device model detected from the connection (name-based today). Set on
/// connect, reset to [DeviceModel.unknown] on disconnect. A future SysEx
/// identity / VID:PID path would set this directly.
final detectedDeviceModelProvider = StateProvider<DeviceModel>(
  (ref) => .unknown,
);

/// A manual model override from the settings selector; wins over detection when
/// non-null (null = Auto). The escape hatch for a device whose enumeration name
/// we don't recognize.
final deviceModelOverrideProvider = StateProvider<DeviceModel?>((ref) => null);

/// The model the UI gates the effect/amp pickers on: the manual override if set,
/// otherwise the detected model.
final effectiveDeviceModelProvider = Provider<DeviceModel>(
  (ref) =>
      ref.watch(deviceModelOverrideProvider) ??
      ref.watch(detectedDeviceModelProvider),
);

/// True while an auto-reconnect retry loop is in flight (disables Connect,
/// prevents a second overlapping loop).
final reconnectingProvider = StateProvider<bool>((ref) => false);

/// Transport connection-state events (BLE true/false); empty for USB.
final connectionEventsProvider = StreamProvider<bool>(
  (ref) =>
      ref.watch(deviceServiceProvider).connectionEvents ??
      const Stream<bool>.empty(),
);
