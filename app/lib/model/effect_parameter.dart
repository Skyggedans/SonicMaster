import 'widget_type.dart';

/// One tweakable parameter of an effect (a knob, toggle, or selector).
class EffectParameter {
  const EffectParameter({
    required this.name,
    required this.algId,
    required this.defaultValue,
    required this.widgetType,
    this.min,
    this.max,
    this.step,
    this.unit,
    this.options,
    this.syncToggleAlgId,
  });

  final String name;
  final int algId;
  final num defaultValue;
  final WidgetType widgetType;
  final num? min;
  final num? max;
  final num? step;
  final String? unit;
  final List<String>? options;

  /// When non-null, this (Hz) knob is tempo-sync-capable: while the toggle at
  /// this algId is on, the pedal reinterprets the value as a note-division
  /// index (see `syncDivisions`) and the editor shows a division selector
  /// instead of the Hz knob.
  final int? syncToggleAlgId;

  factory EffectParameter.fromJson(Map<String, dynamic> json) =>
      EffectParameter(
        name: json['name'] as String,
        algId: json['algId'] as int,
        defaultValue: json['defaultValue'] as num,
        widgetType: WidgetType.fromCode(json['widgetType'] as int),
        min: json['min'] as num?,
        max: json['max'] as num?,
        step: json['step'] as num?,
        unit: json['unit'] as String?,
        options: (json['options'] as List?)?.cast<String>(),
        syncToggleAlgId: json['syncToggleAlgId'] as int?,
      );
}
