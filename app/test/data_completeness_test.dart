// Per-effect completeness guard. Loads the shipped data assets and asserts the
// effect library + parameter command tables are internally complete, so a
// future data/extractor change can't silently drop an effect, a widget's
// options, or a value's command. (Audited manually first; this locks it in.)

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/model/effect_parameter.dart';
import 'package:sonicmaster/protocol/param_value_key.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataAssets data;

  setUpAll(() async {
    data = await DataAssets.load();
  });

  // The exact values a param's control can produce, matching ModuleEditor:
  // toggle -> 0/1; select -> option indices; knob/eqBand -> min..max by step
  // (snapped to the same precision the slider uses).
  List<num> producibleValues(EffectParameter p) {
    switch (p.widgetType) {
      case .toggle:
        return const [0, 1];
      case .select:
        final n = p.options?.length ?? 0;

        return List.generate(n, (i) => i);
      case .knob:
      case .eqBand:
        final min = p.min;
        final max = p.max;

        if (min == null || max == null) return const [];

        final step = (p.step ?? 1) == 0 ? 1.0 : (p.step ?? 1).toDouble();
        final divisions = ((max - min) / step).round();

        return List.generate(
          divisions + 1,
          (i) => step == step.roundToDouble()
              ? (min + i * step).round()
              : double.parse((min + i * step).toStringAsFixed(1)),
        );
    }
  }

  // All (moduleId, effectId) pairs the UI can reach.
  Iterable<(int, int)> moduleEffects() sync* {
    for (final m in Iterable<int>.generate(10)) {
      for (final id in data.commands.effectIdsFor(m)) {
        yield (m, id);
      }
    }
  }

  test('every module effect exists in the library', () {
    for (final (m, id) in moduleEffects()) {
      expect(
        data.effects.byId(id),
        isNotNull,
        reason:
            'module $m effect $id is in effectTypes but missing from the '
            'effect library',
      );
    }
  });

  test('knob/eqBand params have min & max; select params have options', () {
    for (final (_, id) in moduleEffects()) {
      for (final p in data.effects.byId(id)!.params) {
        switch (p.widgetType) {
          case .knob:
          case .eqBand:
            expect(p.min, isNotNull, reason: 'effect $id / ${p.name}: no min');
            expect(p.max, isNotNull, reason: 'effect $id / ${p.name}: no max');
          case .select:
            expect(
              p.options != null && p.options!.isNotEmpty,
              true,
              reason: 'effect $id / ${p.name}: select with no options',
            );
          case .toggle:
            break;
        }
      }
    }
  });

  test('parameter command table covers every producible value', () {
    final gaps = <String>[];

    for (final (m, id) in moduleEffects()) {
      for (final p in data.effects.byId(id)!.params) {
        for (final v in producibleValues(p)) {
          final cmd = data.commands.parameterCommand(
            m,
            p.algId,
            formatParamValueKey(v),
          );

          if (cmd == null) {
            gaps.add(
              'module $m effect $id ${p.name} algId ${p.algId} value $v',
            );
          }
        }
      }
    }

    expect(
      gaps,
      isEmpty,
      reason:
          'missing parameter commands (${gaps.length}):\n'
          '${gaps.take(20).join('\n')}',
    );
  });
}
