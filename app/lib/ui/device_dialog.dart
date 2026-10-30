import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../device/transport.dart';
import '../device/transport_factory.dart';
import '../device/web_capabilities.dart';
import '../state/device_providers.dart';
import '../state/reconnect.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';

/// The shortest the picker's content (title, toggle, list area, actions) may
/// get before it scrolls as a whole: the pinned chrome (about 146 px in
/// Oswald) plus a 74-px list area. Only a transient case gets below it: a soft
/// keyboard still closing after Connect was tapped from a focused field.
const double _minPickerContentHeight = 220;

/// Connect target popped for a web BLE pick. The browser chooser returns the
/// actual device (the transport takes the first result), so this is only the
/// persisted/displayed label — the pedal's default BLE name.
const _webBleTarget = 'Smart Box BLE';

/// What the device picker says when the browser has no Web MIDI (with SysEx),
/// by the browser's OS: on web, [defaultTargetPlatform] follows the user agent
/// (iPadOS counts as iOS; Android in desktop-site mode counts as Linux).
String webMidiUnsupportedMessage(TargetPlatform platform) => switch (platform) {
  .android =>
    'Web MIDI is not available in this browser.\n'
        'Use Chrome or Samsung Internet.',
  .iOS => _iosCannotConnect,
  _ =>
    'Web MIDI is not available in this browser.\n'
        'Use Chrome, Edge, Opera, or Firefox.',
};

/// What the device picker says when the browser has no Web Bluetooth, by the
/// browser's OS. Only desktop Linux gets the flag hint: Chrome ships the API
/// switched off there.
String webBluetoothUnsupportedMessage(TargetPlatform platform) =>
    switch (platform) {
      .android =>
        'Web Bluetooth is not available in this browser.\n'
            'Use Chrome or Samsung Internet.',
      .iOS => _iosCannotConnect,
      .linux =>
        'Web Bluetooth is not available.\n'
            'Use Chrome, Edge, or Opera. On Linux, enable\n'
            'chrome://flags/#enable-experimental-web-platform-features',
      _ =>
        'Web Bluetooth is not available.\n'
            'Use Chrome, Edge, or Opera.',
    };

/// Every iPhone and iPad browser runs on WebKit, which has neither Web MIDI
/// nor Web Bluetooth.
const _iosCannotConnect =
    'No iPhone or iPad browser can connect to the pedal:\n'
    'none of them supports Web MIDI or Web Bluetooth.\n'
    'Use Chrome on Android, or a desktop browser.';

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

      if (kind == .usb && !isWebMidiSupported) {
        rows.value = const [];
        error.value = webMidiUnsupportedMessage(defaultTargetPlatform);

        return;
      }

      if (kind == .ble && !isWebBluetoothSupported) {
        rows.value = const [];
        error.value = webBluetoothUnsupportedMessage(defaultTargetPlatform);

        return;
      }

      // Web Bluetooth has no passive scan — the browser exposes its own device
      // chooser (shown as a button below), so there is nothing to enumerate.
      if (kIsWeb && kind == .ble) {
        rows.value = const [];

        return;
      }

      try {
        final scanned = kind == .usb
            ? [
                for (final d in await enumerateMidiDevices())
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
                for (final d in await enumerateBleDevices())
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

    final isWebBle = kIsWeb && kind == .ble;

    final Widget content = isWebBle && isWebBluetoothSupported
        ? WebBleChooser(onSelect: () => Navigator.pop(context, _webBleTarget))
        : currentRows == null
        ? const Center(child: SonicSpinner())
        : errorText != null
        ? DeviceStateMessage(errorText)
        : currentRows.isEmpty
        ? DeviceStateMessage(
            kind == .usb ? 'No USB MIDI devices found' : 'No BLE devices found',
          )
        : ListView(
            padding: EdgeInsets.zero,
            children: [for (final r in currentRows) _DeviceRow(r)],
          );

    return DeviceDialogShell(
      content: content,
      transport: kind,
      onTransport: setKind,
      onRescan: isWebBle || currentRows == null ? null : scan,
    );
  }
}

/// The picker chrome (title, USB/BLE toggle, a content area, and Rescan/Cancel
/// actions) around a caller-provided [content].
///
/// The content area flexes: 300 px when there is room (the desktop look),
/// whatever a phone leaves otherwise, while the title, the toggle and the
/// actions stay pinned. Below [_minPickerContentHeight] the whole content
/// scrolls instead. One structure at every height, so a keyboard opening or
/// closing never remounts [content].
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
      isScrollable: false,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(
                constraints.maxHeight,
                _minPickerContentHeight,
              ),
            ),
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
                Flexible(child: SizedBox(height: 300, child: content)),
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
          ),
        ),
      ),
    );
  }
}

/// A centred status line in the picker's content area ("No USB MIDI devices
/// found", a scan error, an unsupported-browser hint). It scrolls when a phone
/// leaves the area shorter than the text.
class DeviceStateMessage extends StatelessWidget {
  const DeviceStateMessage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _CenteredScroll(
      child: Text(text, textAlign: .center, style: AppText.dialogBody),
    );
  }
}

/// Web BLE content: a prompt plus a button that hands off to the browser's own
/// device chooser. Web Bluetooth has no passive scan and `requestDevice` needs a
/// user gesture, so the button tap both starts the chooser and carries the
/// transient activation into the connect flow.
class WebBleChooser extends StatelessWidget {
  const WebBleChooser({super.key, required this.onSelect});

  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    // Only the explanation scrolls: on a short phone it gives way, and the
    // button, the only way on, stays in view.
    return Center(
      child: Column(
        mainAxisSize: .min,
        children: [
          const Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: .min,
                children: [
                  Icon(
                    Icons.bluetooth_searching,
                    color: Color(0xFF9A9488),
                    size: 40,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Your browser picks the Bluetooth device.\n'
                    'Choose your pedal in the chooser that opens.',
                    textAlign: .center,
                    style: AppText.dialogBody,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SonicButton(label: 'Select Bluetooth device', onPressed: onSelect),
        ],
      ),
    );
  }
}

/// Centres [child] in the picker's content area and lets it scroll when a
/// phone leaves the area shorter than it.
class _CenteredScroll extends StatelessWidget {
  const _CenteredScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(child: SingleChildScrollView(child: child));
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
