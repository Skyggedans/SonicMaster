// PresetFieldsPanel: Preset Vol + Preset BPM, laid out to mirror the module
// knob row — side by side on one line, stacked when the module knobs wrapped.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/preset_fields_panel.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool stacked}) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Align(
            alignment: Alignment.topLeft,
            child: PresetFieldsPanel(
              presetVolume: 60,
              presetBpm: 120,
              isLoading: false,
              topSpacer: 12,
              stacked: stacked,
              patchKnobKey: const Key('patch'),
              onVolume: (_) {},
              onBpm: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  KnobControl knob(WidgetTester tester, String label) =>
      tester.widget<KnobControl>(
        find.byWidgetPredicate((w) => w is KnobControl && w.label == label),
      );

  // The load-bearing invariant: the panel's width must NOT change with the
  // layout. The effect editor beside it is an Expanded, so a width that varied
  // with `stacked` would change the editor width, flip whether its knobs wrap,
  // flip `stacked`, and oscillate every frame (the flicker bug). Same width in
  // both states => no feedback loop.
  testWidgets('panel width is identical whether stacked or side by side', (
    tester,
  ) async {
    await pump(tester, stacked: false);
    final flat = tester.getSize(find.byType(PresetFieldsPanel)).width;

    await pump(tester, stacked: true);
    final tall = tester.getSize(find.byType(PresetFieldsPanel)).width;

    expect(tall, flat);
  });

  testWidgets('renders both preset-level knobs with the BPM range', (
    tester,
  ) async {
    await pump(tester, stacked: false);

    expect(find.byType(KnobControl), findsNWidgets(2));

    final vol = knob(tester, 'Preset Vol');
    final bpm = knob(tester, 'BPM');

    expect(vol.value, 60);
    expect(bpm.value, 120);
    expect(bpm.min, 40);
    expect(bpm.max, 260);
  });

  Offset center(WidgetTester tester, String label) => tester.getCenter(
    find.byWidgetPredicate((w) => w is KnobControl && w.label == label),
  );

  testWidgets('side by side when the module knobs fit one row', (tester) async {
    await pump(tester, stacked: false);

    final vol = center(tester, 'Preset Vol');
    final bpm = center(tester, 'BPM');

    // Same row: BPM sits to the RIGHT of Preset Vol, on the same line.
    expect(bpm.dx, greaterThan(vol.dx));
    expect((bpm.dy - vol.dy).abs(), lessThan(1));
  });

  testWidgets('stacked when the module knobs wrapped to a second row', (
    tester,
  ) async {
    await pump(tester, stacked: true);

    final vol = center(tester, 'Preset Vol');
    final bpm = center(tester, 'BPM');

    // Second floor: BPM sits BELOW Preset Vol, on the same column.
    expect(bpm.dy, greaterThan(vol.dy));
    expect((bpm.dx - vol.dx).abs(), lessThan(1));
  });
}
