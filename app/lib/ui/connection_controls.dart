import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_providers.dart';
import '../state/reconnect.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'device_dialog.dart';
import 'sonic_controls.dart';

/// The Connect action for the current state: opens the device picker and
/// connects to the pick. Null when there is nothing to connect: a pedal is
/// connected, or an auto-reconnect retry is in flight. It never disconnects,
/// so a stray tap can't drop a live pedal (reconnecting needs the picker
/// again, and a fresh Bluetooth chooser on the web). Shared by the well's
/// Connect button and the compact title bar's whole-well target.
VoidCallback? connectAction(BuildContext context, WidgetRef ref) {
  if (ref.watch(connectionStateProvider) || ref.watch(reconnectingProvider)) {
    return null;
  }

  return () => pickAndConnect(context, ref);
}

/// The top bar's device well: the device name (when connected) or
/// "Disconnected", a colour-coded status dot, and a compact Connect/Disconnect
/// push-button to its right. The USB/BLE picker lives inside [pickAndConnect].
class ConnectionControls extends ConsumerWidget {
  const ConnectionControls({super.key, this.hasStatusLabel = true});

  /// Whether the device name / "Disconnected" label leads the well. The
  /// compact title bar drops it (and its gap): the green glyph or the red dot
  /// already tells connected from not, and the bar has no room for a name.
  final bool hasStatusLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(connectionStateProvider);
    final deviceName = ref.watch(connectedDeviceNameProvider);
    final transport = ref.watch(transportKindProvider);

    final statusLabel = isConnected
        ? (deviceName ?? 'Connected')
        : 'Disconnected';

    return Row(
      mainAxisSize: .min,
      children: [
        if (hasStatusLabel) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              statusLabel,
              maxLines: 1,
              overflow: .ellipsis,
              style: AppText.connectionLabel,
            ),
          ),
          const SizedBox(width: 8),
        ],
        // Connected: a green interface glyph (USB fork / Bluetooth "B").
        // Disconnected: a red dot.
        if (isConnected)
          Icon(
            transport == .ble ? Icons.bluetooth : Icons.usb,
            size: 15,
            color: Palette.ledConnected,
          )
        else
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: .circle,
              color: Palette.ledDisconnected,
            ),
          ),
        const SizedBox(width: 10),
        // Compact Connect / Disconnect, right of the dot.
        SonicButton(
          label: isConnected ? 'Disconnect' : 'Connect',
          height: 26,
          minWidth: 0,
          isAccent: !isConnected,
          onPressed: isConnected
              ? () => disconnectDevice(ref)
              : connectAction(context, ref),
        ),
      ],
    );
  }
}
