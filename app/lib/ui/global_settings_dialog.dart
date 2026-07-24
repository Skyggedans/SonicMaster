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

/// EXP/FS Target labels, indexed by wire value. EXP mode uses [_expTargetLabels]
/// (reg 0x17); SingleFS and DualFS use [_fsTargetLabels] (reg 0x16).
const _expTargetLabels = <String>[
  'VOL',
  'FX1',
  'DRV',
  'AMP',
  'IR',
  'FX2',
  'DLY',
  'RVB',
];

const _fsTargetLabels = <String>[
  'Preset-',
  'Preset+',
  'Tap Tempo',
  'NR',
  'FX1',
  'DRV',
  'AMP',
  'IR',
  'EQ',
  'FX2',
  'DLY',
  'RVB',
  'CTRL 1',
  'CTRL 2',
  'Drum',
  'REC/Play',
  'Loop Stop',
  'Tuner',
];

/// Device-global settings, mirroring the Android app's Settings screen: the four
/// dB level knobs plus Mode / Re-amp / EXP-FS Type / Backlight / ECO / Power, and
/// the app-side device-model selector. All device writes are synthesized frames.
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
          const Text('Settings', style: AppText.dialogTitle),
          const SizedBox(height: 8),
          if (g == null)
            const SizedBox(
              height: 120,
              child: Center(
                child: Text('Reading settings…', style: AppText.dialogBody),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.62,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  children: [
                    const _SectionHeader('Levels'),
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
                    const _SectionHeader('USB'),
                    _SettingRow(
                      label: 'Mode',
                      child: SonicSegmented<int>(
                        value: g.mode,
                        segments: const [
                          (value: 0, label: 'Dry'),
                          (value: 1, label: 'Wet'),
                        ],
                        onChanged: (v) => setGlobalSetting(ref, 'mode', v),
                      ),
                    ),
                    _SwitchRow(
                      label: 'Re-amp',
                      name: 'reamp',
                      value: g.reamp,
                      isLoading: isLoading,
                    ),
                    const _SectionHeader('EXP/FS'),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: .stretch,
                        mainAxisSize: .min,
                        children: [
                          const Text('Type', style: AppText.dialogBody),
                          const SizedBox(height: 6),
                          SonicSegmented<int>(
                            value: g.expFsType,
                            isExpanded: true,
                            segments: const [
                              (value: 0, label: 'EXP'),
                              (value: 1, label: 'SingleFS'),
                              (value: 2, label: 'DualFS'),
                            ],
                            onChanged: (v) =>
                                setGlobalSetting(ref, 'expFsType', v),
                          ),
                        ],
                      ),
                    ),
                    if (g.expFsType == 0)
                      _TargetRow(
                        label: 'Target',
                        labels: _expTargetLabels,
                        value: g.expFsTarget,
                        isLoading: isLoading,
                      )
                    else if (g.expFsType == 1)
                      _TargetRow(
                        label: 'Target',
                        labels: _fsTargetLabels,
                        value: g.expFsTarget,
                        isLoading: isLoading,
                      )
                    else ...[
                      _TargetRow(
                        label: 'Func 1',
                        labels: _fsTargetLabels,
                        value: g.expFsTarget,
                        isLoading: isLoading,
                      ),
                      _TargetRow(
                        label: 'Func 2',
                        labels: _fsTargetLabels,
                        value: g.expFsTarget2,
                        isLoading: isLoading,
                        isFunc2: true,
                      ),
                    ],
                    const _SectionHeader('Display'),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Align(
                        alignment: .centerLeft,
                        child: KnobControl(
                          value: g.backlight,
                          min: 0,
                          max: 10,
                          step: 1,
                          label: 'Backlight',
                          isEnabled: !isLoading,
                          size: 60,
                          onChanged: (v) =>
                              setGlobalSetting(ref, 'backlight', v.round()),
                        ),
                      ),
                    ),
                    _SwitchRow(
                      label: 'ECO',
                      name: 'eco',
                      value: g.eco,
                      isLoading: isLoading,
                    ),
                    const _SectionHeader('Power'),
                    _SwitchRow(
                      label: 'Confirm',
                      name: 'powerConfirm',
                      value: g.powerConfirm,
                      isLoading: isLoading,
                    ),
                    _SwitchRow(
                      label: 'Batt Only',
                      name: 'battOnly',
                      value: g.battOnly,
                      isLoading: isLoading,
                    ),
                    const _SectionHeader('Reset'),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: _ResetButton(),
                    ),
                    const SizedBox(height: 16),
                    const _DeviceModelSelector(),
                  ],
                ),
              ),
            ),
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

/// A small uppercase group header, e.g. "USB" / "Display".
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: AppText.controlLabel.copyWith(
          color: Palette.textDim,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// A label on the left and a trailing [child] control on the right.
class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.dialogBody)),
          child,
        ],
      ),
    );
  }
}

/// A labelled on/off [SonicToggle] wired to [setGlobalSetting] (0/1). Disabled
/// while a device read is in flight.
class _SwitchRow extends ConsumerWidget {
  const _SwitchRow({
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
    return _SettingRow(
      label: label,
      child: SonicToggle(
        value: value == 1,
        onChanged: isLoading
            ? null
            : (on) => setGlobalSetting(ref, name, on ? 1 : 0),
      ),
    );
  }
}

/// An EXP/FS Target dropdown wired to [setExpFsTarget]. [labels] indexes the wire
/// value; [isFunc2] selects the DualFS second slot.
class _TargetRow extends ConsumerWidget {
  const _TargetRow({
    required this.label,
    required this.labels,
    required this.value,
    required this.isLoading,
    this.isFunc2 = false,
  });

  final String label;
  final List<String> labels;
  final int value;
  final bool isLoading;
  final bool isFunc2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = [
      for (final (i, name) in labels.indexed) (value: i, label: name),
    ];

    return _SettingRow(
      label: label,
      child: SonicDropdown<int>(
        value: value.clamp(0, labels.length - 1),
        items: items,
        width: 156,
        isEnabled: !isLoading,
        onChanged: (v) => setExpFsTarget(ref, v, isFunc2: isFunc2),
      ),
    );
  }
}

/// "Reset to factory settings" button, gated behind a confirmation dialog so it
/// can't be triggered by accident. Sends the reset command, after which the pedal
/// reboots and disconnects.
class _ResetButton extends ConsumerWidget {
  const _ResetButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: .centerLeft,
      child: SonicButton(
        label: 'Reset to factory settings',
        onPressed: () => _confirm(context, ref),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final isConfirmed = await showSonicDialog<bool>(
      context: context,
      builder: (dialogContext) => SonicDialog(
        maxWidth: 360,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            const Text(
              'Reset to factory settings?',
              style: AppText.dialogTitle,
            ),
            const SizedBox(height: 12),
            const Text(
              'This restores all presets and settings to factory defaults. '
              'The pedal will reboot and disconnect.',
              style: AppText.dialogBody,
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: .end,
              children: [
                SonicButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(dialogContext, false),
                ),
                const SizedBox(width: 10),
                SonicButton(
                  label: 'Reset',
                  isAccent: true,
                  onPressed: () => Navigator.pop(dialogContext, true),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (isConfirmed == true) await factoryReset(ref);
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
