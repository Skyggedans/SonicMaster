import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/preset_drawer.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

import '../support/page_harness.dart';
import '../support/view_helpers.dart';

void main() {
  Future<List<num>> pump(
    WidgetTester tester, {
    num value = 50,
    num min = 0,
    num max = 100,
    num step = 1,
    SonicMetrics metrics = SonicMetrics.regular,
  }) async {
    final changed = <num>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SonicMetricsScope(
            metrics: metrics,
            child: KnobControl(
              value: value,
              min: min,
              max: max,
              step: step,
              label: 'X',
              onChanged: changed.add,
            ),
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

  // Double-taps the [readout] to open the inline value editor.
  Future<void> openEditor(WidgetTester tester, Finder readout) async {
    final spot = tester.getCenter(readout);

    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(spot);
    await tester.pump();
  }

  EditableText editorOf(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText));

  group('typing a value on a phone keyboard', () {
    testWidgets('compact: the editor opens with the whole value selected', (
      tester,
    ) async {
      await pump(tester, value: 50, metrics: SonicMetrics.compact);
      await openEditor(tester, find.text('50'));

      expect(
        editorOf(tester).controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('regular: the caret opens after the value (unchanged)', (
      tester,
    ) async {
      await pump(tester, value: 50);
      await openEditor(tester, find.text('50'));

      expect(
        editorOf(tester).controller.selection,
        const TextSelection.collapsed(offset: 2),
      );
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('compact: a signed range opens a signed number pad', (
      tester,
    ) async {
      await pump(
        tester,
        value: 0,
        min: -20,
        max: 20,
        metrics: SonicMetrics.compact,
      );
      await openEditor(tester, find.text('0'));

      expect(
        editorOf(tester).keyboardType,
        const TextInputType.numberWithOptions(signed: true, decimal: true),
      );
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('compact: an unsigned range keeps the decimal number pad', (
      tester,
    ) async {
      await pump(tester, value: 50, metrics: SonicMetrics.compact);
      await openEditor(tester, find.text('50'));

      final editor = editorOf(tester);

      expect(
        editor.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      expect(editor.autocorrect, isFalse);
      expect(editor.enableSuggestions, isFalse);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('compact: a decimal comma commits at a fractional step', (
      tester,
    ) async {
      final changed = await pump(
        tester,
        value: 5,
        max: 10,
        step: 0.1,
        metrics: SonicMetrics.compact,
      );

      await openEditor(tester, find.text('5'));
      await tester.enterText(find.byType(EditableText), '2,5');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump();

      expect(changed, [2.5]);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('regular: a signed range keeps today\'s keyboard (unchanged)', (
      tester,
    ) async {
      await pump(tester, value: 0, min: -20, max: 20);
      await openEditor(tester, find.text('0'));

      final editor = editorOf(tester);

      expect(
        editor.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      expect(editor.autocorrect, isTrue);
      expect(editor.enableSuggestions, isTrue);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('regular: a decimal comma commits nothing (unchanged)', (
      tester,
    ) async {
      final changed = await pump(tester, value: 5, max: 10, step: 0.1);

      await openEditor(tester, find.text('5'));
      await tester.enterText(find.byType(EditableText), '2,5');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump();

      expect(changed, isEmpty);
      expect(find.byType(EditableText), findsNothing);
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('the editor losing focus', () {
    testWidgets('compact: commits the typed value once', (tester) async {
      final changed = await pump(tester, metrics: SonicMetrics.compact);

      await openEditor(tester, find.text('50'));
      await tester.enterText(find.byType(EditableText), '64');
      // What closing the drawer or showing the rotate prompt does to it.
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      await tester.pump();

      expect(changed, [64]);
      expect(find.byType(EditableText), findsNothing);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('compact: Done still commits exactly once', (tester) async {
      final changed = await pump(tester, metrics: SonicMetrics.compact);

      await openEditor(tester, find.text('50'));
      await tester.enterText(find.byType(EditableText), '64');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump();
      await tester.pump();

      expect(changed, [64]);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('compact: Escape still reverts without sending', (
      tester,
    ) async {
      final changed = await pump(tester, metrics: SonicMetrics.compact);

      await openEditor(tester, find.text('50'));
      await tester.enterText(find.byType(EditableText), '64');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();

      expect(changed, isEmpty);
      expect(find.byType(EditableText), findsNothing);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('regular: keeps editing and sends nothing (unchanged)', (
      tester,
    ) async {
      final changed = await pump(tester);

      await openEditor(tester, find.text('50'));
      await tester.enterText(find.byType(EditableText), '64');
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      await tester.pump();

      expect(changed, isEmpty);
      expect(find.byType(EditableText), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));
    });

    // A phone user typing a Master Vol value presses Back (once the keyboard
    // is down): the drawer closes under the open editor and must not drop the
    // typed level.
    testWidgets('Back closing the drawer commits a Master Vol being typed', (
      tester,
    ) async {
      final container = await pumpPage(tester, size: const Size(852, 393));
      final masterVol = find.descendant(
        of: find.byType(PresetDrawer),
        matching: find.byType(KnobControl),
      );

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // The list at the top, Master Vol in view, whatever the reveal did.
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(PresetDrawer),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pump();
      await openEditor(
        tester,
        find.descendant(of: masterVol, matching: find.text('75')),
      );
      await tester.enterText(
        find.descendant(of: masterVol, matching: find.byType(EditableText)),
        '60',
      );
      await simulateSystemBack(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(container.read(globalVolumeProvider), 60);
      expect(
        find.descendant(of: masterVol, matching: find.byType(EditableText)),
        findsNothing,
      );
    });
  });

  group('the readout row takes the double-tap', () {
    // Double-taps 3 px inside the dial's left edge, level with the digits: in
    // the readout row, but beside the digits themselves.
    Future<void> doubleTapBesideDigits(WidgetTester tester) async {
      final dial = tester.getRect(find.byKey(const Key('knob')));
      final spot = Offset(dial.left + 3, tester.getCenter(find.text('50')).dy);

      await tester.tapAt(spot);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(spot);
      await tester.pump();
    }

    testWidgets('compact: beside the digits opens the editor', (tester) async {
      await pump(tester, metrics: SonicMetrics.compact);
      await doubleTapBesideDigits(tester);

      expect(find.byType(EditableText), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('regular: beside the digits does nothing (unchanged)', (
      tester,
    ) async {
      await pump(tester);
      await doubleTapBesideDigits(tester);

      expect(find.byType(EditableText), findsNothing);
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
