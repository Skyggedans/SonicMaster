import 'dart:convert';

import '../device/device_model.dart';
import 'data_assets.dart';
import 'effect_definition.dart';
import 'effect_parameter.dart';
import 'preset_json.dart';

/// Physical module slots in the order the catalog lists them.
const _catalogModules = [
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

/// The effect ids [model] can select in [module]. NR has no entry in the
/// command library (its single effect, Gate, is id 1).
List<int> _effectIds(DataAssets data, DeviceModel model, String module) {
  final moduleId = data.modules.idOf(module)!;
  final ids = data.capabilities.availableEffectIds(
    data.commands,
    model,
    moduleId,
  );

  return ids.isEmpty && module == 'NR' ? const [1] : ids;
}

String _paramLine(EffectParameter p) {
  final range = switch (p.widgetType) {
    .toggle => '0|1',
    .select => [
      for (final (i, o) in (p.options ?? const <String>[]).indexed) '$i=$o',
    ].join('|'),
    _ => '${p.min}..${p.max}${p.unit == null ? '' : ' ${p.unit}'}',
  };

  return '${p.name} [$range, default ${p.defaultValue}]';
}

String _effectLine(EffectDefinition e) {
  final params = e.params.map(_paramLine).join('; ');

  return '- "${e.name}"${e.descriptionEn.isEmpty ? '' : ' (${e.descriptionEn})'}'
      ': ${params.isEmpty ? 'no parameters' : params}';
}

/// Every module with the effects (and parameter ranges) [model] supports, as
/// text for the LLM.
String effectCatalog(DataAssets data, DeviceModel model) {
  final out = StringBuffer();

  for (final module in _catalogModules) {
    out.writeln('## $module');

    for (final id in _effectIds(data, model, module)) {
      final def = data.effects.byId(id);

      if (def != null) out.writeln(_effectLine(def));
    }

    out.writeln();
  }

  return out.toString();
}

/// A schema-complete example preset: each module's first effect at its default
/// parameters. Built from the data tables so it can't drift from the importer.
Map<String, dynamic> presetTemplate(DataAssets data, DeviceModel model) {
  final modules = <String, dynamic>{};

  for (final module in _catalogModules) {
    final ids = _effectIds(data, model, module);
    final def = ids.isEmpty ? null : data.effects.byId(ids.first);

    modules[module] = {
      'enabled': true,
      'effect': def?.name,
      'parameters': {
        for (final p in def?.params ?? const <EffectParameter>[])
          p.name: p.defaultValue,
      },
    };
  }

  return {
    'version': presetJsonVersion,
    'presetName': 'My Preset',
    'ampMode': 'Normal',
    'presetVolume': 75,
    'presetBpm': 120,
    'modules': modules,
    'signalChain': _catalogModules,
  };
}

/// The system instruction that makes the model answer with an importable preset
/// JSON for [model] — the same schema the app's Import/Export uses.
String buildPresetSystemPrompt(DataAssets data, DeviceModel model) {
  final template = const JsonEncoder.withIndent(
    '  ',
  ).convert(presetTemplate(data, model));

  return '''
You design presets for the Sonicake ${data.capabilities.displayName(model)} guitar multi-effects pedal. Given the user's description (a song, an artist, a tone, a style), reply with ONE JSON document describing a preset that recreates that tone as closely as the pedal allows.

The pedal's signal path has nine modules: NR (noise reduction), FX1, DRV (drive), AMP, IR (cabinet), EQ, FX2, DLY (delay) and RVB (reverb).

# Rules
- Reply with the JSON object only: no markdown, no commentary.
- Follow the template below exactly: same keys, same module names.
- "effect" must be one of the effect names listed for that module in the catalog, spelled exactly as listed. Never invent an effect. Use null to leave a module without an effect.
- "parameters" must contain every parameter of the chosen effect, keyed by the exact parameter name, with a number inside the range listed. For choice parameters use the numeric index (the number before "="); for on/off parameters use 0 or 1.
- Set "enabled" to false for modules the tone doesn't need, and true for those it does.
- "ampMode" must be "Normal".
- "presetName" is at most 10 characters.
- "presetVolume" is 0-100 and "presetBpm" is 40-260 (match the song's tempo when known).
- "signalChain" lists all nine module names exactly once. DRV, AMP, IR and EQ must stay together in that order; the other five (NR, FX1, FX2, DLY, RVB) can be placed anywhere around that block.

# Template
$template

# Catalog of modules, effects and parameters (name [range, default])
${effectCatalog(data, model)}''';
}
