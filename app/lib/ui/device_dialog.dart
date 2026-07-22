import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_btleplug/flutter_btleplug.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../device/transport.dart';
import '../state/device_providers.dart';
import '../state/reconnect.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';

/// Opens the device picker; if the user picks a device, connects over the
/// chosen transport and persists the intent. No-op on cancel.
Future<void> pickAndConnect(BuildContext context, WidgetRef ref) async {
  final target = await showSonicDialog<String>(
    context: context,
    builder: (_) => const DeviceDialog(),
  );

  if (target == null) return; // cancelled

  await connectAndPersist(ref, target: target);
}

/// Transport-aware device picker: a USB/BLE toggle plus the matching device
/// list (USB-MIDI ports, or scanned BLE devices). Sets [transportKindProvider]
/// to the toggled transport, and pops the chosen device name (the connect
/// target) — or null on cancel.
class DeviceDialog extends HookConsumerWidget {
  const DeviceDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = useState<List<_DevRow>?>(null); // null = scanning
    final error = useState<String?>(null);

    Future<void> scan() async {
      rows.value = null;
      error.value = null;

      final kind = ref.read(transportKindProvider);

      try {
        final scanned = kind == .usb
            ? [
                for (final d in await scanUsbMidi())
                  _DevRow(
                    name: d.name,
                    subtitle: d.connectable
                        ? 'USB MIDI · in + out'
                        : d.hasInput
                        ? 'input only'
                        : 'output only',
                    isEnabled: d.connectable,
                    isUsb: true,
                  ),
              ]
            : [
                for (final d in await scanBle())
                  _DevRow(
                    name: d.name,
                    subtitle: '${d.address}   rssi ${d.rssi}',
                    isEnabled: d.name.isNotEmpty,
                    isUsb: false,
                  ),
              ];

        if (context.mounted) rows.value = scanned;
      } catch (e) {
        // e.g. the Bluetooth adapter is off, or MIDI enumeration failed.
        if (context.mounted) {
          rows.value = const [];
          error.value = 'Scan failed: $e';
        }
      }
    }

    void setKind(TransportKind k) {
      if (k == ref.read(transportKindProvider)) return;

      // Switching transport rebuilds DeviceService; it starts disconnected.
      ref.read(transportKindProvider.notifier).state = k;
      ref.read(connectionStateProvider.notifier).state = false;
      scan();
    }

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) => scan());

      return null;
    }, const []);

    final kind = ref.watch(transportKindProvider);
    final currentRows = rows.value;
    final errorText = error.value;

    final Widget content = currentRows == null
        ? const Center(child: SonicSpinner())
        : errorText != null
        ? Center(
            child: Text(
              errorText,
              textAlign: .center,
              style: AppText.dialogBody,
            ),
          )
        : currentRows.isEmpty
        ? Center(
            child: Text(
              kind == .usb
                  ? 'No USB MIDI devices found'
                  : 'No BLE devices found',
              style: AppText.dialogBody,
            ),
          )
        : ListView(
            padding: EdgeInsets.zero,
            children: [for (final r in currentRows) _DeviceRow(r)],
          );

    return DeviceDialogShell(
      content: content,
      transport: kind,
      onTransport: setKind,
      onRescan: currentRows == null ? null : scan,
    );
  }
}

/// The picker chrome (title, USB/BLE toggle, a fixed-height content area, and
/// Rescan/Cancel actions) around a caller-provided [content].
class DeviceDialogShell extends StatelessWidget {
  const DeviceDialogShell({
    super.key,
    required this.content,
    required this.transport,
    required this.onTransport,
    required this.onRescan,
  });

  final Widget content;
  final TransportKind transport;
  final ValueChanged<TransportKind> onTransport;
  final VoidCallback? onRescan;

  @override
  Widget build(BuildContext context) {
    return SonicDialog(
      maxWidth: 440,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          const Text('Select a device', style: AppText.dialogTitle),
          const SizedBox(height: 14),
          SonicSegmented<TransportKind>(
            value: transport,
            isExpanded: true,
            height: 36,
            segments: const [
              (value: .usb, label: 'USB'),
              (value: .ble, label: 'BLE'),
            ],
            onChanged: onTransport,
          ),
          const SizedBox(height: 12),
          SizedBox(height: 300, child: content),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: .end,
              children: [
                SonicButton(label: 'Rescan', onPressed: onRescan),
                const SizedBox(width: 10),
                SonicButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single tappable device entry in the picker list.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow(this.row);

  final _DevRow row;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: .opaque,
      onTap: row.isEnabled ? () => Navigator.pop(context, row.name) : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Opacity(
          opacity: row.isEnabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                Icon(
                  row.isUsb ? Icons.usb : Icons.bluetooth,
                  color: const Color(0xFF9A9488),
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        row.name.isEmpty ? '(unnamed)' : row.name,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: AppText.deviceRowTitle,
                      ),
                      const SizedBox(height: 2),
                      Text(row.subtitle, style: AppText.deviceRowSub),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DevRow {
  const _DevRow({
    required this.name,
    required this.subtitle,
    required this.isEnabled,
    required this.isUsb,
  });

  final String name;
  final String subtitle;
  final bool isEnabled;
  final bool isUsb;
}
