import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/knob_control.dart';

void main() {
  Future<List<num>> pump(
    WidgetTester tester, {
    num value = 50,
    num min = 0,
    num max = 100,
    num step = 1,
  }) async {
    final changed = <num>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnobControl(
            value: value,
            min: min,
            max: max,
            step: step,
            label: 'X',
            onChanged: changed.add,
          ),
        ),
      ),
    );

    return changed;
  }

  Future<void> scroll(WidgetTester tester, double dy) async {
    final c = tester.getCenter(find.byKey(const Key('knob')));
    final p = TestPointer(1, .mouse);

    await tester.sendEventToBinding(p.hover(c));
    await tester.sendEventToBinding(p.scroll(Offset(0, dy)));
    await tester.pump();
  }

  testWidgets('scroll up nudges by step', (tester) async {
    final changed = await pump(tester, value: 50);

    await scroll(tester, -100);
    expect(changed.last, 51);
  });

  testWidgets('scroll down at min clamps', (tester) async {
    final changed = await pump(tester, value: 0);

    await scroll(tester, 100);
    expect(changed.last, 0);
  });

  testWidgets('vertical drag up increases the value', (tester) async {
    final changed = await pump(tester, value: 50);
    final c = tester.getCenter(find.byKey(const Key('knob')));
    final g = await tester.startGesture(c);

    await g.moveTo(c + const Offset(0, -40)); // up (screen y-down)
    await g.up();
    await tester.pump();
    expect(changed, isNotEmpty);
    expect(changed.last, greaterThan(50));
  });

  testWidgets('vertical drag down decreases the value', (tester) async {
    final changed = await pump(tester, value: 50);
    final c = tester.getCenter(find.byKey(const Key('knob')));
    final g = await tester.startGesture(c);

    await g.moveTo(c + const Offset(0, 40)); // down
    await g.up();
    await tester.pump();
    expect(changed, isNotEmpty);
    expect(changed.last, lessThan(50));
  });

  testWidgets('double-tap the readout, type + submit commits clamped', (
    tester,
  ) async {
    final changed = await pump(tester, value: 50);
    final loc = tester.getCenter(find.text('50'));

    await tester.tapAt(loc);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(loc);
    await tester.pump();
    expect(find.byType(EditableText), findsOneWidget);
    await tester.enterText(find.byType(EditableText), '999');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();
    expect(changed.last, 100);
    expect(find.byType(EditableText), findsNothing);
    // Flush the DoubleTapGestureRecognizer's internal kDoubleTapMinTime
    // tracker timer so tearDown doesn't trip on a pending Timer.
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('Escape reverts without a change', (tester) async {
    final changed = await pump(tester, value: 50);
    final loc = tester.getCenter(find.text('50'));

    await tester.tapAt(loc);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(loc);
    await tester.pump();
    await tester.enterText(find.byType(EditableText), '999');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(changed, isEmpty);
    expect(find.byType(EditableText), findsNothing);
    // Flush the DoubleTapGestureRecognizer's internal kDoubleTapMinTime
    // tracker timer so tearDown doesn't trip on a pending Timer.
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('renders (paints) without error at several values', (
    tester,
  ) async {
    for (final v in [0, 25, 50, 100]) {
      await pump(tester, value: v);
      expect(tester.takeException(), isNull);
    }
  });
}
