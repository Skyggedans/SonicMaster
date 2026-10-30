import 'data_assets.dart';
import 'decoded_preset_state.dart';

/// The `version` value every exported preset carries.
const presetJsonVersion = '1.0';

/// Physical module slots, in a stable export order (ids 0-8). The amp slot
/// (AMP, id 3) is emitted as "Clone" (effect/params from id 9) in clone mode.
const _physicalModules = [
  'NR',
  'FX1',
  'DRV',
  'AMP',
  'IR',
  'EQ',
  'FX2',
  'DLY',
  'RVB',
];

/// Serializes the live decoded preset to the web-compatible JSON schema.
Map<String, dynamic> presetToJson({
  required DecodedPresetState state,
  required Map<int, int> selected,
  required Map<int, Map<int, num>> params,
  required DataAssets data,
  String? presetName,
}) {
  final modules = <String, dynamic>{};

  for (final name in _physicalModules) {
    final clone = name == 'AMP' && state.isCloneMode;
    final effModuleId = clone ? 9 : (data.modules.idOf(name) ?? -1);
    final key = clone ? 'Clone' : name;
    final fxId = selected[effModuleId];
    final def = fxId == null ? null : data.effects.byId(fxId);
    final vals = params[effModuleId] ?? const <int, num>{};
    final paramMap = <String, dynamic>{};

    if (def != null) {
      for (final p in def.params) {
        if (vals[p.algId] != null) paramMap[p.name] = vals[p.algId];
      }
    }

    modules[key] = {
      'enabled': state.moduleStates[name] ?? false,
      'effect': def?.name,
      'parameters': paramMap,
    };
  }

  return {
    'version': presetJsonVersion,
    'presetName': presetName ?? '',
    'ampMode': state.isCloneMode ? 'Clone' : 'Normal',
    'presetVolume': state.presetVolume,
    'presetBpm': state.presetBpm,
    'modules': modules,
    'signalChain': state.chainOrder,
  };
}

/// A converted preset ready to push to the device (ids, not names).
class ImportedPreset {
  ImportedPreset({
    required this.isCloneMode,
    required this.presetVolume,
    required this.presetBpm,
    required this.moduleStates,
    required this.selectedEffects,
    required this.parameters,
    required this.chainOrder,
    required this.warnings,
  });

  final bool isCloneMode;
  final int presetVolume;
  final int presetBpm;
  final Map<int, bool> moduleStates; // physical moduleId -> on
  final Map<int, int> selectedEffects; // effect moduleId (9 for clone) -> fxId
  final Map<int, Map<int, num>> parameters; // effect moduleId -> algId -> value
  final List<String> chainOrder; // module names
  final List<String> warnings;
}

/// Validates and converts a preset JSON doc. Throws [FormatException] on an
/// unsupported version or an unknown effect name; collects non-fatal issues
/// (unknown module, clamped/defaulted params) into `warnings`.
ImportedPreset importedPresetFromJson(
  Map<String, dynamic> json,
  DataAssets data,
) {
  if (json['version'] != presetJsonVersion) {
    throw FormatException('Unsupported preset version: ${json['version']}');
  }

  final warnings = <String>[];
  final isCloneMode = json['ampMode'] == 'Clone';
  final presetVolume = (((json['presetVolume'] as num?) ?? 75).clamp(
    0,
    100,
  )).round();
  // Optional key (added after v1.0 shipped): absent in older exports -> default.
  // Range mirrors the hardware / official app (40–260).
  final presetBpm = (((json['presetBpm'] as num?) ?? 120).clamp(40, 260))
      .round();

  final moduleStates = <int, bool>{};
  final selectedEffects = <int, int>{};
  final parameters = <int, Map<int, num>>{};

  int? effectIdByName(String name) {
    for (final e in data.effects.effects.entries) {
      if (e.value.name == name) return e.key;
    }

    return null;
  }

  final modules =
      (json['modules'] as Map?)?.cast<String, dynamic>() ?? const {};

  modules.forEach((key, raw) {
    final m = (raw as Map).cast<String, dynamic>();
    final isClone = key == 'Clone';
    final physId = data.modules.idOf(isClone ? 'AMP' : key);

    if (physId == null) {
      warnings.add('Unknown module "$key" — skipped');
      return;
    }

    final effModuleId = isClone ? 9 : physId;

    moduleStates[physId] = (m['enabled'] as bool?) ?? true;

    final effectName = m['effect'] as String?;

    if (effectName == null) return;

    final fxId = effectIdByName(effectName);

    if (fxId == null) {
      throw FormatException(
        'Module "$key" references unknown effect "$effectName"',
      );
    }

    selectedEffects[effModuleId] = fxId;

    final def = data.effects.byId(fxId);

    if (def == null) return;

    final jsonParams =
        (m['parameters'] as Map?)?.cast<String, dynamic>() ?? const {};

    final upper = <String, dynamic>{
      for (final e in jsonParams.entries) e.key.toUpperCase(): e.value,
    };

    final out = <int, num>{};

    for (final p in def.params) {
      var v = upper[p.name.toUpperCase()] as num?;

      if (v == null) {
        v = p.defaultValue;
        warnings.add(
          '$key.${p.name} missing — using default ${p.defaultValue}',
        );
      } else if (p.min != null && p.max != null) {
        final c = v.clamp(p.min!, p.max!);

        if (c != v) {
          warnings.add('$key.${p.name} clamped from $v to $c');
          v = c;
        }
      }

      out[p.algId] = v;
    }

    parameters[effModuleId] = out;
  });

  return ImportedPreset(
    isCloneMode: isCloneMode,
    presetVolume: presetVolume,
    presetBpm: presetBpm,
    moduleStates: moduleStates,
    selectedEffects: selectedEffects,
    parameters: parameters,
    chainOrder: ((json['signalChain'] as List?) ?? const []).cast<String>(),
    warnings: warnings,
  );
}
