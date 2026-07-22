import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/effect_library.dart';
import 'package:sonicmaster/model/widget_type.dart';

void main() {
  final json =
      jsonDecode(File('assets/data/effect_library.json').readAsStringSync())
          as Map<String, dynamic>;

  final lib = EffectLibrary.fromJson(json);

  test('parses a simple knob effect (Gate #1)', () {
    final gate = lib.byId(1)!;

    expect(gate.name, 'Gate');
    expect(gate.params, hasLength(1));

    final thre = gate.params.single;

    expect(thre.name, 'THRE');
    expect(thre.algId, 0);
    expect(thre.widgetType, WidgetType.knob);
    expect(thre.min, 0);
    expect(thre.max, 100);
  });

  test(
    'parses toggle and select widget types (Boost #105, Touch Wah #103)',
    () {
      final boost = lib.byId(105)!;
      final plus3 = boost.params.firstWhere((p) => p.name == '+3dB');

      expect(plus3.widgetType, WidgetType.toggle);

      final touchWah = lib.byId(103)!;
      final mode = touchWah.params.firstWhere((p) => p.name == 'Mode');

      expect(mode.widgetType, WidgetType.select);
      expect(mode.options, ['Guitar', 'Bass']);
    },
  );

  test('parses bipolar EQ band params as eqBand (GT EQ 1 #501)', () {
    final band = lib.byId(501)!.params.firstWhere((p) => p.name == '125Hz');

    expect(band.widgetType, WidgetType.eqBand);
    expect(band.min, -50);
    expect(band.max, 50);
  });

  test('parses float params with unit (Auto Wah #104 Rate in Hz)', () {
    final rate = lib.byId(104)!.params.firstWhere((p) => p.name == 'Rate');

    expect(rate.unit, 'Hz');
    expect(rate.step, 0.1);
    expect(rate.max, 10.0);
  });

  test(
    'sync-capable tempo params are knobs pointing at a real Sync toggle',
    () {
      var syncCapable = 0;

      for (final e in lib.effects.values) {
        for (final p in e.params) {
          if (p.syncToggleAlgId == null) continue;

          syncCapable++;
          // The gated control is a tempo knob — Hz for modulation Rate, ms for
          // DLY Time. Both are the slot the firmware rereads as a division
          // index once the gate engages.
          expect(p.widgetType, WidgetType.knob, reason: '${e.name}/${p.name}');
          expect(p.unit, anyOf('Hz', 'ms'), reason: '${e.name}/${p.name}');

          // …and the referenced algId is a real toggle in the same effect.
          final gate = e.params.firstWhere(
            (q) => q.algId == p.syncToggleAlgId,
            orElse: () => throw StateError(
              '${e.name}: syncToggleAlgId ${p.syncToggleAlgId} not found',
            ),
          );

          expect(gate.widgetType, WidgetType.toggle, reason: e.name);
        }
      }

      // 11 recovered modulations (every one except C-Wah) + 10 whose Sync the
      // desktop capture missed (Auto Wah, A/B-Chorus, Flanger, Phaser, Vibe,
      // Vibrato, Tremolo, Sine/Bias Trem) + 15 of the 16 DLY voicings.
      //
      // Slap is the deliberate exception: it is the one DLY with no Sync at all
      // — alg 3 falls through to slot 0 on the pedal — which fits a slapback
      // (Time 20-300ms). It still has Trail. Measured, not inferred: every algId
      // here came off the device via tools/re/find_sync.py, and they follow no
      // pattern (Phaser@1 … Auto Wah@6; DLY@3 but Sweep@6).
      expect(syncCapable, 36);
    },
  );

  test('Fullchor #119 Rate is tempo-sync-capable via the Sync toggle', () {
    final rate = lib.byId(119)!.params.firstWhere((p) => p.name == 'Rate');

    expect(rate.syncToggleAlgId, 2);
    expect(rate.unit, 'Hz');
  });

  test('every effect parses without throwing', () {
    expect(lib.effects.length, greaterThan(50));

    for (final e in lib.effects.values) {
      expect(e.name, isNotEmpty);

      for (final p in e.params) {
        expect(p.name, isNotEmpty);
      }
    }
  });
}
