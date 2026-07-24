import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/chain_view.dart';
import 'package:sonicmaster/ui/led_button.dart';

/// A movable module in [ChainView] wraps its [ModuleCard] in a
/// [LongPressDraggable] inside a [DragTarget] (reorder by long-press drag).
/// These tests pin the gesture contract that composition relies on: a plain tap
/// (no long press) must still reach the card's own select gesture and the inner
/// LedButton's toggle — the drag machinery must not swallow taps.
void main() {
  Widget host(Widget card) => MaterialApp(
    home: Scaffold(
      body: DragTarget<int>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (_) {},
        builder: (context, candidate, rejected) => LongPressDraggable<int>(
          data: 0,
          feedback: const SizedBox.shrink(),
          child: card,
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
}
