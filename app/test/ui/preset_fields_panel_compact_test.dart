import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/preset_fields_panel.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

import '../support/fonts.dart';
import '../support/view_helpers.dart';

/// PresetFieldsPanel per density: a width fixed by the mode alone (the
/// flicker-loop guard), panel-size knobs (the stacked test compares like with
/// like), and a side-by-side row that wraps instead of overflowing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadOswald);

  Future<void> pumpPanel(
    WidgetTester tester, {
    required SonicMetrics metrics,
    required bool isStacked,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SonicMetricsScope(
            metrics: metrics,
            child: Align(
              alignment: Alignment.topLeft,
              child: PresetFieldsPanel(
                presetVolume: 100,
                presetBpm: 260,
                isLoading: false,
                topSpacer: 12,
                stacked: isStacked,
                patchKnobKey: const Key('patch'),
                onVolume: (_) {},
                onBpm: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder knob(String label) =>
      find.byWidgetPredicate((w) => w is KnobControl && w.label == label);

  for (final metrics in const [SonicMetrics.regular, SonicMetrics.compact]) {
    final mode = metrics.isCompact ? 'compact' : 'regular';

    testWidgets('$mode: the width is fixed whether stacked or not', (
      tester,
    ) async {
      await pumpPanel(tester, metrics: metrics, isStacked: false);

      final flat = tester.getSize(find.byType(PresetFieldsPanel)).width;

      await pumpPanel(tester, metrics: metrics, isStacked: true);

      expect(flat, metrics.presetPanelWidth);
      expect(tester.getSize(find.byType(PresetFieldsPanel)).width, flat);
    });

    testWidgets('$mode: Preset Vol and BPM are panel-size knobs', (
      tester,
    ) async {
      await pumpPanel(tester, metrics: metrics, isStacked: false);

      for (final label in const ['Preset Vol', 'BPM']) {
        expect(
          tester.widget<KnobControl>(knob(label)).size,
          metrics.panelKnobSize,
        );
      }
    });

    // The Row this replaced: both cells on one line, centred as one run with
    // an 8-px gap. The Wrap lays a fitting pair out identically.
    testWidgets('$mode: side by side is one centred run, 8 px apart', (
      tester,
    ) async {
      await pumpPanel(tester, metrics: metrics, isStacked: false);

      expectNoOverflow(tester);

      final panel = tester.getRect(find.byType(PresetFieldsPanel));
      final volume = tester.getRect(knob('Preset Vol'));
      final bpm = tester.getRect(knob('BPM'));
      // Inside the SonicSurface's 1-px border and 12-px horizontal padding.
      final inner = panel.width - 2 - 24;
      final run = volume.width + 8 + bpm.width;

      expect(run, lessThanOrEqualTo(inner));
      expect(volume.left, closeTo(panel.left + 13 + (inner - run) / 2, 0.01));
      expect(bpm.left, closeTo(volume.right + 8, 0.01));
      expect(bpm.top, volume.top);
    });
  }

  // 'PRESET VOL' at 12 px is 58 px wide: the compact pair fills 168 of 168.
  // A browser text size of 140% widens the caption past the 72-px dial, so BPM
  // moves to a second line rather than overflowing the fixed 194-px panel.
  testWidgets('compact: a 1.4x text scale wraps BPM instead of overflowing', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      metrics: SonicMetrics.compact,
      isStacked: false,
      textScale: 1.4,
    );

    expectNoOverflow(tester);

    final volume = tester.getRect(knob('Preset Vol'));
    final bpm = tester.getRect(knob('BPM'));

    expect(bpm.top, greaterThanOrEqualTo(volume.bottom));
    expect(tester.getSize(find.byType(PresetFieldsPanel)).width, 194);
  });
}
