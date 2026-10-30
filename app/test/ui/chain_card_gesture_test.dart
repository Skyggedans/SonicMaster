import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/chain_view.dart';
import 'package:sonicmaster/ui/led_button.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

/// A movable module in [ChainView] wraps its [ModuleCard] in a
/// [LongPressDraggable] inside a [DragTarget] (reorder by long-press drag).
/// These tests pin the gesture contract that composition relies on: a plain tap
/// (no long press) must still reach the card's own select gesture and the inner
/// LedButton's toggle — the drag machinery must not swallow taps.
void main() {
  Widget host(Widget card, {SonicMetrics metrics = SonicMetrics.regular}) =>
      MaterialApp(
        home: Scaffold(
          body: SonicMetricsScope(
            metrics: metrics,
            child: DragTarget<int>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (_) {},
              builder: (context, candidate, rejected) =>
                  LongPressDraggable<int>(
                    data: 0,
                    feedback: const SizedBox.shrink(),
                    child: card,
                  ),
            ),
          ),
        ),
      );

  testWidgets('tapping a draggable card body fires onSelect', (tester) async {
    var selects = 0;
    var toggles = 0;

    await tester.pumpWidget(
      host(
        ModuleCard(
          iconId: 0,
          name: 'NR',
          effect: 'Gate',
          isOn: true,
          isSelected: false,
          isEnabled: true,
          onSelect: () => selects++,
          onToggle: () => toggles++,
        ),
      ),
    );
    await tester.tap(find.text('NR'));
    await tester.pump();
    expect(
      selects,
      1,
      reason: 'card tap must survive the long-press draggable',
    );
    expect(toggles, 0, reason: 'tapping the body must not toggle');
  });

  testWidgets('tapping the LedButton fires onToggle, not onSelect', (
    tester,
  ) async {
    var selects = 0;
    var toggles = 0;

    await tester.pumpWidget(
      host(
        ModuleCard(
          iconId: 0,
          name: 'NR',
          effect: 'Gate',
          isOn: true,
          isSelected: false,
          isEnabled: true,
          onSelect: () => selects++,
          onToggle: () => toggles++,
        ),
      ),
    );
    await tester.tap(find.byType(LedButton));
    await tester.pump();
    expect(toggles, 1, reason: 'LED tap must survive the long-press draggable');
    expect(selects, 0, reason: 'the inner LED tap must win over card select');
  });

  // Pumps a card in [metrics], then taps 3 px below and 3 px above its LED:
  // outside the LED itself, inside the space around it. Returns the select
  // and toggle counts.
  Future<({int selects, int toggles})> tapAroundLed(
    WidgetTester tester, {
    required SonicMetrics metrics,
    bool isEnabled = true,
  }) async {
    var selects = 0;
    var toggles = 0;

    await tester.pumpWidget(
      host(
        ModuleCard(
          iconId: 0,
          name: 'NR',
          effect: 'Gate',
          isOn: true,
          isSelected: false,
          isEnabled: isEnabled,
          onSelect: () => selects++,
          onToggle: () => toggles++,
        ),
        metrics: metrics,
      ),
    );

    final led = tester.getRect(find.byType(LedButton));

    await tester.tapAt(led.bottomCenter + const Offset(0, 3));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(led.topCenter - const Offset(0, 3));
    await tester.pump(const Duration(milliseconds: 300));

    return (selects: selects, toggles: toggles);
  }

  testWidgets('compact: taps just above and below the LED toggle it', (
    tester,
  ) async {
    final taps = await tapAroundLed(tester, metrics: SonicMetrics.compact);

    expect(taps, (selects: 0, toggles: 2));
  });

  testWidgets('regular: the same taps still select the card (unchanged)', (
    tester,
  ) async {
    final taps = await tapAroundLed(tester, metrics: SonicMetrics.regular);

    expect(taps, (selects: 2, toggles: 0));
  });

  // A phone user taps next to an LED while a preset load is in flight (the
  // card's toggle is disabled): the bigger target must not toggle a module.
  testWidgets('compact, load in flight: taps beside the LED never toggle', (
    tester,
  ) async {
    final taps = await tapAroundLed(
      tester,
      metrics: SonicMetrics.compact,
      isEnabled: false,
    );

    expect(taps, (selects: 2, toggles: 0));
  });
}
