import 'effect_parameter.dart';

/// A single effect model and its parameters (e.g. "COMP 1").
class EffectDefinition {
  const EffectDefinition({
    required this.id,
    required this.name,
    required this.descriptionEn,
    required this.params,
  });

  final int id;
  final String name;
  final String descriptionEn;
  final List<EffectParameter> params;

  factory EffectDefinition.fromJson(int id, Map<String, dynamic> json) =>
      EffectDefinition(
        id: id,
        name: json['name'] as String,
        descriptionEn: (json['descriptionEn'] as String?) ?? '',
        params: ((json['alg'] as List?) ?? const [])
            .map((e) => EffectParameter.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
