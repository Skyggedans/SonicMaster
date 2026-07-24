import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_model.dart';
import '../state/connection_prefs.dart';
import '../state/data_providers.dart';
import '../state/device_providers.dart';
import '../state/preset_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'knob_control.dart';
import 'sonic_controls.dart';

/// Device-global level controls (input / FX-rec / BT-rec / monitor, −20..20 dB),
/// shown as our rotary knobs.
class GlobalSettingsDialog extends ConsumerWidget {
  const GlobalSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(globalSettingsProvider);
    final isLoading = ref.watch(presetLoadingProvider);

    return SonicDialog(
      maxWidth: 440,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          const Text('Global settings', style: AppText.dialogTitle),
          const SizedBox(height: 8),
          if (g == null)
            const SizedBox(
              height: 120,
              child: Center(
                child: Text('Reading settings…', style: AppText.dialogBody),
              ),
            )
          else
            Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                _LevelKnob(
                  label: 'Input',
                  name: 'inputLevel',
                  value: g.inputLevel,
                  isLoading: isLoading,
                ),
                _LevelKnob(
                  label: 'FX Rec',
                  name: 'fxRecLevel',
                  value: g.fxRecLevel,
                  isLoading: isLoading,
                ),
                _LevelKnob(
                  label: 'BT Rec',
                  name: 'btRecLevel',
                  value: g.btRecLevel,
                  isLoading: isLoading,
                ),
                _LevelKnob(
                  label: 'Monitor',
                  name: 'monitorLevel',
                  value: g.monitorLevel,
                  isLoading: isLoading,
                ),
              ],
            ),
          const SizedBox(height: 16),
          const _DeviceModelSelector(),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: SonicButton(
              label: 'Close',
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// One −20..20 dB rotary level knob wired to [setGlobalLevel].
class _LevelKnob extends ConsumerWidget {
  const _LevelKnob({
    required this.label,
    required this.name,
    required this.value,
    required this.isLoading,
  });

  final String label;
  final String name;
  final int value;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KnobControl(
      value: value,
      min: -20,
      max: 20,
      step: 1,
      label: label,
      unit: ' dB',
      isEnabled: !isLoading,
      size: 72,
      onChanged: (v) => setGlobalLevel(ref, name, v.round()),
    );
  }
}

/// Auto / Pocket Master / Smart Box model selector. "Auto" (null override)
/// follows detection and shows the detected model; picking a model manually
/// overrides detection and persists across launches.
class _DeviceModelSelector extends ConsumerWidget {
  const _DeviceModelSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = ref.watch(deviceModelOverrideProvider);
    final detected = ref.watch(detectedDeviceModelProvider);
    final caps = ref.watch(dataAssetsProvider).valueOrNull?.capabilities;
    final hint = override == null
        ? 'Auto — ${caps?.displayName(detected) ?? 'detecting…'}'
        : 'Manual';

    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: [
        Row(
          children: [
            const Text('Device model', style: AppText.dialogBody),
            const Spacer(),
            Text(
              hint,
              style: AppText.dialogBody.copyWith(color: Palette.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SonicSegmented<DeviceModel>(
          value: override ?? DeviceModel.unknown,
          isExpanded: true,
          segments: const [
            (value: DeviceModel.unknown, label: 'Auto'),
            (value: DeviceModel.pocketMaster, label: 'Pocket Master'),
            (value: DeviceModel.smartBox, label: 'Smart Box'),
          ],
          onChanged: (v) {
            final next = v == .unknown ? null : v;

            ref.read(deviceModelOverrideProvider.notifier).state = next;
            unawaited(
              ref.read(connectionPrefsProvider).saveModelOverride(next),
            );
          },
        ),
      ],
    );
  }
}
