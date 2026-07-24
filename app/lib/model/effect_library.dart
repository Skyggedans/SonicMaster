import 'effect_definition.dart';

/// All effect definitions, keyed by effect id.
class EffectLibrary {
  const EffectLibrary(this.effects);

  final Map<int, EffectDefinition> effects;

  EffectDefinition? byId(int id) => effects[id];

  factory EffectLibrary.fromJson(Map<String, dynamic> json) => EffectLibrary({
    for (final e in json.entries)
      int.parse(e.key): EffectDefinition.fromJson(
        int.parse(e.key),
        e.value as Map<String, dynamic>,
      ),
  });
}
