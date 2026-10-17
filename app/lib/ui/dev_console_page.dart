import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../device/traffic_log.dart';
import '../protocol/inbound_message.dart';
import '../state/device_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';
import 'sonic_field.dart';

/// Developer console docked at the bottom of the work area: connect to the
/// pedal, send a read-only query, and watch the classified inbound messages.
/// [onClose] hides the panel (the X in the header).
class DevConsolePanel extends HookConsumerWidget {
  const DevConsolePanel({super.key, required this.onClose});

  final VoidCallback onClose;

  // Read-only "request global settings" command (8080 stripped on send).
  static const _globalSettingsQuery = '8080F00B0900010000000201020100F7';

  String _describe(InboundMessage m) => switch (m) {
    DataFrame(:final hex) => 'DataFrame ${hex.length ~/ 2}B  $hex',
    MalformedFrame(:final hex) => 'Malformed  $hex',
    _ => m.runtimeType.toString(),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = useState<List<String>>(const []);
    final marker = useTextEditingController();
    final isCapturing = useState(TrafficLog.isEnabled);

    Future<void> toggleCapture(bool on) async {
      isCapturing.value = on;
      TrafficLog.isEnabled = on;

      if (on) {
        TrafficLog.marker('capture started');

        final path = await TrafficLog.ensureFile();

        if (context.mounted) log.value = ['CAPTURE → $path', ...log.value];
      }
    }

    void mark() {
      final label = marker.text.trim();

      if (label.isEmpty) return;

      TrafficLog.marker(label);
      log.value = ['MARK  $label', ...log.value];
      marker.clear();
    }

    Future<void> query() async {
      try {
        await ref.read(deviceServiceProvider).sendFrame(_globalSettingsQuery);
      } catch (e) {
        log.value = ['SEND ERROR: $e', ...log.value];
      }
    }

    // Accumulate classified inbound messages into the log; surface errors too
    // so a dead pipeline is never mistaken for "no messages yet".
    ref.listen(inboundProvider, (_, next) {
      next.when(
        data: (msg) => log.value = [_describe(msg), ...log.value],
        error: (e, _) => log.value = ['STREAM ERROR: $e', ...log.value],
        loading: () {},
      );
    });

    final ports = ref.watch(midiPortsProvider);
    final connected = ref.watch(connectionStateProvider);

    return ColoredBox(
      color: Palette.background,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: .center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: .center,
                    children: [
                      SonicButton(
                        label: 'Query global settings',
                        onPressed: connected ? query : null,
                      ),
                      SonicButton(
                        label: 'Clear log',
                        onPressed: () => log.value = [],
                      ),
                      Row(
                        mainAxisSize: .min,
                        children: [
                          SonicToggle(
                            value: isCapturing.value,
                            onChanged: (v) => toggleCapture(v),
                          ),
                          const SizedBox(width: 8),
                          const Text('CAPTURE', style: AppText.ledLabel),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  connected ? Icons.usb : Icons.usb_off,
                  color: connected ? Palette.ledConnected : Palette.textDim,
                ),
                const SizedBox(width: 8),
                SonicIconButton(
                  icon: Icons.close,
                  onPressed: onClose,
                  padding: const EdgeInsets.only(left: 10),
                ),
              ],
            ),
          ),
          if (isCapturing.value)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: SonicField(
                      controller: marker,
                      hintText: 'marker (e.g. "enter tuner")',
                      onSubmitted: (_) => mark(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SonicButton(label: 'Mark', onPressed: mark),
                ],
              ),
            ),
          // Everything below the fixed button row scrolls as one region so the
          // MIDI-ports list can never push the log past the panel's bottom (the
          // panel lives in a fixed, drag-resizable height). The log keeps its
          // virtualized builder via a sliver.
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: .stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Column(
                          crossAxisAlignment: .start,
                          children: [
                            const Text('MIDI PORTS', style: AppText.ledLabel),
                            const SizedBox(height: 6),
                            ports.when(
                              data: (list) => Column(
                                crossAxisAlignment: .start,
                                children: [
                                  for (final p in list)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            p.isInput
                                                ? Icons.input
                                                : Icons.output,
                                            size: 18,
                                            color: Palette.textDim,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(p.name, style: AppText.input),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              loading: () => const Padding(
                                padding: EdgeInsets.all(8),
                                child: SonicSpinner(),
                              ),
                              error: (e, _) =>
                                  Text('ports error: $e', style: AppText.input),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 1,
                        color: Palette.railBorder,
                        margin: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Inbound', style: AppText.boldLabel),
                        ),
                      ),
                    ],
                  ),
                ),
                SliverList.builder(
                  itemCount: log.value.length,
                  itemBuilder: (_, i) =>
                      Text(log.value[i], style: AppText.monoLog),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
