// The Sync gate's UI: engaging Sync must swap the Rate Hz knob for a
// note-division dropdown, because the pedal reads that same slot as a division
// index once the gate is on (confirmed on device — see tools/re/probe_slot.py).
// Auto Wah is the interesting case: its Sync sits at algId 6, a slot the
// desktop-tool capture missed entirely.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/module_editor.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/tap_tempo_control.dart';

import '../support/test_assets.dart';

void main() {
  final assets = loadTestDataAssets();

  // Renders [moduleId]'s editor holding [fxId] with [params] already applied.
  Future<void> pumpEditor(
    WidgetTester tester,
    int moduleId,
    int fxId,
    Map<int, num> params,
  ) async {
    final container = ProviderContainer(
      overrides: [
        dataAssetsProvider.overrideWith((_) => assets),
        currentSelectedEffectsProvider.overrideWith((_) => {moduleId: fxId}),
        currentParametersProvider.overrideWith((_) => {moduleId: params}),
      ],
    );

    addTearDown(container.dispose);
    await container.read(dataAssetsProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Directionality(
          textDirection: .ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 900,
                child: SingleChildScrollView(child: ModuleEditor(moduleId)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The module header carries its own on/off SonicToggle, so a byType lookup
  // is ambiguous — go through the labelled PanelCell instead.
  Finder inCell(String label, Type control) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PanelCell && w.label == label),
    matching: find.byType(control),
  );

  // A knob is returned bare (it carries its own label); only the sync-engaged
  // division dropdown gets wrapped in a PanelCell.
  Finder tempoKnob(String label) =>
      find.byWidgetPredicate((w) => w is KnobControl && w.label == label);

  // Every effect whose Sync the desktop capture missed. Each algId was measured
  // on device (tools/re/find_sync.py), never inferred — they follow no pattern:
  // Phaser@1 … Auto Wah@6, DLY@3 but Sweep@6. The gated param is per-effect too
  // (Phaser's Rate is at alg 0; DLY gates Time, in ms, not Rate).
  const cases = [
    (
      name: 'Auto Wah',
      fxId: 104,
      moduleId: 1,
      tempo: 'Rate',
      tempoAlg: 1,
      syncAlg: 6,
    ),
    (
      name: 'Auto Wah in FX2',
      fxId: 104,
      moduleId: 6,
      tempo: 'Rate',
      tempoAlg: 1,
      syncAlg: 6,
    ),
    (
      name: 'A-Chorus',
      fxId: 106,
      moduleId: 1,
      tempo: 'Rate',
      tempoAlg: 1,
      syncAlg: 3,
    ),
    (
      name: 'B-Chorus',
      fxId: 107,
      moduleId: 1,
      tempo: 'Rate',
      tempoAlg: 1,
      syncAlg: 3,
    ),
    (
      name: 'Flanger',
      fxId: 108,
      moduleId: 1,
      tempo: 'Rate',
      tempoAlg: 1,
      syncAlg: 4,
    ),
    (
      name: 'Phaser',
      fxId: 109,
      moduleId: 1,
      tempo: 'Rate',
      tempoAlg: 0,
      syncAlg: 1,
    ),
    (
      name: 'Vibe',
      fxId: 110,
      moduleId: 1,
      tempo: 'Rate',
      tempoAlg: 1,
      syncAlg: 2,
    ),
    (
      name: 'Vibrato',
      fxId: 111,
      moduleId: 1,
      tempo: 'Rate',
      tempoAlg: 1,
      syncAlg: 2,
    ),
    (
      name: 'Tremolo',
      fxId: 112,
      moduleId: 1,
      tempo: 'Rate',
      tempoAlg: 1,
      syncAlg: 2,
    ),
    (
      name: 'Sine Trem',
      fxId: 113,
      moduleId: 1,
      tempo: 'Rate',
      tempoAlg: 1,
      syncAlg: 3,
    ),
    (
      name: 'Bias Trem',
      fxId: 114,
      moduleId: 1,
      tempo: 'Rate',
      tempoAlg: 1,
      syncAlg: 3,
    ),
    (
      name: 'DLY Pure',
      fxId: 701,
      moduleId: 7,
      tempo: 'Time',
      tempoAlg: 1,
      syncAlg: 3,
    ),
    (
      name: 'DLY Sweep',
      fxId: 708,
      moduleId: 7,
      tempo: 'Time',
      tempoAlg: 1,
      syncAlg: 6,
    ),
  ];

  for (final c in cases) {
    // A value the param actually allows: Rate is 0.1-10 Hz, DLY Time 20-1000 ms.
    final parked = c.tempo == 'Time' ? 500 : 0.5;

    testWidgets('${c.name}: Sync off -> ${c.tempo} is a plain knob', (
      tester,
    ) async {
      await pumpEditor(tester, c.moduleId, c.fxId, {
        c.tempoAlg: parked,
        c.syncAlg: 0,
      });

      final tempo = tester.widget<KnobControl>(tempoKnob(c.tempo));

      expect(tempo.unit, c.tempo == 'Time' ? 'ms' : 'Hz');
      expect(tempo.value, parked);
      // …and the gate itself is rendered, off.
      expect(
        tester.widget<SonicToggle>(inCell('Sync', SonicToggle)).value,
        isFalse,
      );
    });

    testWidgets('${c.name}: Sync on -> ${c.tempo} is a division dropdown', (
      tester,
    ) async {
      // 4 is what the pedal itself writes into the slot on engaging Sync.
      await pumpEditor(tester, c.moduleId, c.fxId, {
        c.tempoAlg: 4,
        c.syncAlg: 1,
      });

      expect(
        tempoKnob(c.tempo),
        findsNothing,
        reason: 'the ${c.tempo} knob must be gone once Sync is engaged',
      );

      final divisions = tester.widget<SonicDropdown<int>>(
        inCell(c.tempo, SonicDropdown<int>),
      );

      expect(divisions.items.map((i) => i.label).toList(), syncDivisions);
      expect(divisions.value, 4);
      expect(syncDivisions[4], '1/4', reason: 'index 4 is the 1/4 division');
      expect(
        tester.widget<SonicToggle>(inCell('Sync', SonicToggle)).value,
        isTrue,
      );
    });
  }

  // Tap tempo writes milliseconds straight into DLY's Time slot. Engaged, Sync
  // makes the pedal reread that slot as a division index, so a tap would write
  // nonsense — it must not be offered then.
  testWidgets('DLY: tap tempo is offered while Sync is off', (tester) async {
    await pumpEditor(tester, 7, 701, {1: 500, 3: 0});

    expect(find.byType(TapTempoControl), findsOneWidget);
  });

  testWidgets('DLY: tap tempo is withdrawn once Sync is engaged', (
    tester,
  ) async {
    await pumpEditor(tester, 7, 701, {1: 4, 3: 1});

    expect(find.byType(TapTempoControl), findsNothing);
    expect(inCell('Time', SonicDropdown<int>), findsOneWidget);
  });

  // Slap is the one DLY with no Sync: alg 3 falls through to slot 0 on the
  // pedal, which fits a slapback (Time 20-300ms). It still carries Trail.
  testWidgets('DLY Slap has Trail but no Sync gate', (tester) async {
    final slap = assets.effects.byId(702)!;

    expect(slap.params.map((p) => p.name), ['Mix', 'Time', 'F.Back', 'Trail']);
    expect(slap.params.every((p) => p.syncToggleAlgId == null), isTrue);
    expect(slap.params.any((p) => p.algId == 3), isFalse);
  });
}
