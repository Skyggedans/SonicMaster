import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_providers.dart';
import '../state/reconnect.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'device_dialog.dart';
import 'sonic_controls.dart';

/// The top bar's device well: the device name (when connected) or
/// "Disconnected", a colour-coded status dot, and a compact Connect/Disconnect
/// push-button to its right. The USB/BLE picker lives inside [pickAndConnect].
class ConnectionControls extends ConsumerWidget {
  const ConnectionControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(connectionStateProvider);
    final deviceName = ref.watch(connectedDeviceNameProvider);
    final isReconnecting = ref.watch(reconnectingProvider);
    final transport = ref.watch(transportKindProvider);

    final statusLabel = isConnected
        ? (deviceName ?? 'Connected')
        : 'Disconnected';

    return Row(
      mainAxisSize: .min,
      children: [
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
              : (isReconnecting ? null : () => pickAndConnect(context, ref)),
        ),
      ],
    );
  }
}
