import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/effect_parameter.dart';
import '../model/footswitch_assignment.dart';
import '../model/footswitch_state.dart';
import '../state/data_providers.dart';
import '../state/device_providers.dart';
import '../state/names_providers.dart';
import '../state/preset_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'knob_control.dart';
import 'sonic_controls.dart';
import 'tap_tempo_control.dart';
import 'user_ir_actions.dart';
import 'user_profile_actions.dart';

/// Tempo-sync note divisions, indexed by the value the pedal stores in a
/// sync-capable Rate slot (0 = 1/1 … 10 = 1/16). Captured off the device.
const syncDivisions = <String>[
  '1/1', '1/2', '1/2D', '1/2T', '1/4', '1/4D', '1/4T', //
  '1/8', '1/8D', '1/8T', '1/16',
];

/// Editing controls for one module's selected effect. Each change sends a
/// `0408` command via [setParameter].
class ModuleEditor extends ConsumerWidget {
  const ModuleEditor(this.moduleId, {super.key, this.knobRowKey});

  final int moduleId;

  /// Attached to the horizontal knob row so the parent can vertically align the
  /// Patch Vol knob with the effect's knobs.
  final Key? knobRowKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataAssetsProvider).valueOrNull;
    final userNames = ref.watch(userNamesProvider);
    final selected = ref.watch(currentSelectedEffectsProvider);
    final params = ref.watch(currentParametersProvider);
    final modified = ref.watch(presetModifiedProvider);
    final isLoading = ref.watch(presetLoadingProvider);
    final isConnected = ref.watch(connectionStateProvider);
    final model = ref.watch(effectiveDeviceModelProvider);
    final state = ref.watch(currentPresetStateProvider);

    if (data == null) return const SizedBox.shrink();

    // The header on/off toggle acts on the physical slot; the clone amp (editor
    // id 9) toggles the real AMP slot (3).
    final physId = moduleId == 9 ? 3 : moduleId;
    final moduleName = data.modules.nameOf(physId) ?? 'M$moduleId';
    final moduleOn = state?.moduleStates[moduleName] ?? false;
    final fxId = selected[moduleId];
    final def = fxId == null ? null : data.effects.byId(fxId);

    if (def == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('$moduleName — no decoded effect'),
      );
    }

    final values = params[moduleId] ?? const <int, num>{};
    final effectIds = data.capabilities.availableEffectIds(
      data.commands,
      model,
      moduleId,
    );
    // Keep the current effect in the dropdown even if it isn't in the pickable
    // set — some presets hold legacy/hidden effects (e.g. Fullchor / Flash /
    // Doctor CL) that decode but have no select command; this keeps the value
    // valid and the name shown.
    final dropdownIds = effectIds.contains(fxId)
        ? effectIds
        : <int>[fxId!, ...effectIds];

    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              // abbreviation — pinned left
              Text(
                '$moduleName${modified ? '  ✱' : ''}',
                style: AppText.moduleTitle.copyWith(color: Palette.textPrimary),
              ),
              const Spacer(),
              // effect type — dropdown (if selectable) or static name, centered.
              // Gate on dropdownIds (not effectIds): device filtering can narrow
              // the pickable set to one, but a legacy/unsupported current effect
              // is still prepended, and the user must be able to switch off it.
              if (dropdownIds.length > 1)
                SonicDropdown<int>(
                  value: fxId,
                  items: [
                    for (final id in dropdownIds)
                      (
                        value: id,
                        label: effectDisplayName(id, data.effects, userNames),
                      ),
                  ],
                  isEnabled: !isLoading,
                  onChanged: (id) => setEffectType(ref, moduleId, id),
                )
              else
                Text(
                  effectDisplayName(fxId!, data.effects, userNames),
                  style: AppText.controlLabel.copyWith(
                    color: Palette.textPrimary,
                  ),
                ),
              const Spacer(),
              // enabled — BOOST-style toggle (no label), pinned right
              SonicToggle(
                value: moduleOn,
                onChanged: isLoading
                    ? null
                    : (v) => toggleModule(ref, physId, v),
              ),
            ],
          ),
        ),
        // Every control — knobs, toggles, dropdowns — flows in ONE horizontal
        // Wrap like a hardware unit's front panel (always a single row that
        // wraps; never separate full-width rows). DLY (module 7) prepends its
        // tap-tempo cells (TAP / BPM / division / computed-ms) to the same row.
        Builder(
          builder: (context) {
            final cells = [
              // AMP-only: Clone Mode toggle in the settings row (off = Normal/
              // factory amp, on = Clone) — switches the amp slot between factory
              // models (module 3) and the User-Profile clone (module 9).
              if (physId == 3 && state != null)
                PanelCell(
                  label: 'Clone Mode',
                  control: SonicToggle(
                    value: state.isCloneMode,
                    height: 40,
                    onChanged: isLoading ? null : (v) => setAmpMode(ref, v),
                  ),
                ),
              // User-IR slots (module 4, fxId 416–420): load a WAV into the
              // slot, rename it, or clear it.
              if (moduleId == 4 && fxId != null && fxId >= 416 && fxId <= 420)
                UserIrActions(
                  slot: fxId - 416,
                  isEnabled: isConnected && !isLoading,
                  currentName: effectDisplayName(fxId, data.effects, userNames),
                ),
              // User-Profile clone slots (module 9, fxId 901–905): convert a
              // .nam natively and load it into the selected slot.
              if (moduleId == 9 && fxId != null && fxId >= 901 && fxId <= 905)
                UserProfileActions(
                  slot: fxId - 901,
                  isEnabled: isConnected && !isLoading,
                  currentName: effectDisplayName(fxId, data.effects, userNames),
                ),
              for (final p in def.params)
                _control(
                  context,
                  ref,
                  p,
                  values[p.algId] ?? p.defaultValue,
                  isLoading,
                  values,
                ),
              // Per-module footswitch assignment (None/FS1/FS2). Keyed on the
              // physical slot so the clone-amp editor (id 9) drives the amp's.
              if (state != null)
                _FootswitchCell(
                  moduleId: physId,
                  fs1Mask: state.footswitchFs1Mask,
                  fs2Mask: state.footswitchFs2Mask,
                  isEnabled: !isLoading,
                  onChanged: (a) => setModuleFootswitch(ref, physId, a),
                ),
            ];

            // Tap tempo drives DLY's Time slot in milliseconds — but only while
            // Sync is off. Engaged, the pedal rereads that same slot as a
            // note-division index (confirmed: Time 500 -> 4.0 = "1/4"), so a tap
            // would write nonsense into it. Drop back to the plain row then; the
            // division dropdown is the control that belongs there.
            EffectParameter? timeParam;

            if (moduleId == 7) {
              for (final p in def.params) {
                if (p.algId != 1) continue;

                final syncAlg = p.syncToggleAlgId;
                final isSynced = syncAlg != null && (values[syncAlg] ?? 0) != 0;

                if (!isSynced) timeParam = p;

                break;
              }
            }

            return Padding(
              key: knobRowKey,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: timeParam != null
                  ? TapTempoControl(
                      timeMin: (timeParam.min ?? 20).round(),
                      timeMax: (timeParam.max ?? 1000).round(),
                      currentMs: (values[1] ?? timeParam.defaultValue).round(),
                      onSend: (ms) => setParameter(ref, moduleId, 1, ms),
                      trailing: cells,
                    )
                  : Wrap(
                      alignment: .center,
                      spacing: 4,
                      runSpacing: 4,
                      children: cells,
                    ),
            );
          },
        ),
        // Effect description (from the web app data), set off with an accent
        // rule down the left edge.
        if (def.descriptionEn.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            // Recessed black well, like the inactive toggle body.
            child: SonicRecess(
              radius: 10,
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
              child: Text(def.descriptionEn, style: AppText.moduleDescription),
            ),
          ),
      ],
    );
  }

  Widget _control(
    BuildContext context,
    WidgetRef ref,
    EffectParameter param,
    num value,
    bool isLoading,
    Map<int, num> values,
  ) {
    switch (param.widgetType) {
      case .toggle:
        return PanelCell(
          label: param.name,
          control: SonicToggle(
            value: value != 0,
            height: 40,
            onChanged: isLoading
                ? null
                : (v) => setParameter(ref, moduleId, param.algId, v ? 1 : 0),
          ),
        );
      case .select:
        final options = param.options ?? const <String>[];

        if (options.isEmpty) {
          return PanelCell(label: param.name, control: const Text('—'));
        }

        return PanelCell(
          label: param.name,
          control: SonicDropdown<int>(
            value: value.toInt().clamp(0, options.length - 1),
            items: [
              for (final (i, opt) in options.indexed) (value: i, label: opt),
            ],
            isEnabled: !isLoading,
            onChanged: (i) => setParameter(ref, moduleId, param.algId, i),
          ),
        );
      case .knob:
      case .eqBand:
        final syncAlg = param.syncToggleAlgId;

        if (syncAlg != null && (values[syncAlg] ?? 0) != 0) {
          // Tempo-sync engaged: the pedal reads this slot as a note-division
          // index (0 = 1/1 … 10 = 1/16), so show a division selector instead
          // of the Hz knob.
          final idx = value.round().clamp(0, syncDivisions.length - 1);

          return PanelCell(
            label: param.name,
            // Fixed width wide enough for the widest label ("1/2D"/"1/16");
            // passing SonicDropdown.width also sizes its menu to match.
            control: SonicDropdown<int>(
              value: idx,
              width: 112,
              items: [
                for (final (i, div) in syncDivisions.indexed)
                  (value: i, label: div),
              ],
              isEnabled: !isLoading,
              onChanged: (i) => setParameter(ref, moduleId, param.algId, i),
            ),
          );
        }

        return KnobControl(
          value: value,
          min: param.min ?? 0,
          max: param.max ?? 100,
          step: param.step ?? 1,
          label: param.name,
          unit: param.unit,
          size: panelKnobSize,
          isEnabled: !isLoading,
          onChanged: (v) => setParameter(ref, moduleId, param.algId, v),
        );
    }
  }
}

/// The per-module FOOT SWITCH selector: None / FS1 / FS2, laid out as a panel
/// cell in the module's control row. A switch already owned by another module is
/// greyed out — each footswitch has a single global owner.
class _FootswitchCell extends StatelessWidget {
  const _FootswitchCell({
    required this.moduleId,
    required this.fs1Mask,
    required this.fs2Mask,
    required this.isEnabled,
    required this.onChanged,
  });

  final int moduleId;
  final int fs1Mask;
  final int fs2Mask;
  final bool isEnabled;
  final ValueChanged<FootswitchAssignment> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = footswitchAssignmentOf(fs1Mask, fs2Mask, moduleId);
    // A switch is greyed out only once it is FULL (holds the max modules) and
    // this module isn't on it — each switch takes up to [footswitchCapacity].
    final disabled = footswitchDisabledOptions(fs1Mask, fs2Mask, moduleId);

    return PanelCell(
      label: 'Foot Switch',
      control: SonicSegmented<FootswitchAssignment>(
        value: current,
        segments: const [
          (value: FootswitchAssignment.none, label: 'None'),
          (value: FootswitchAssignment.fs1, label: 'FS1'),
          (value: FootswitchAssignment.fs2, label: 'FS2'),
        ],
        disabledValues: disabled,
        onChanged: isEnabled ? onChanged : null,
      ),
    );
  }
}
