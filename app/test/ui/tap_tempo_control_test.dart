import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/sonic_field.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';
import 'package:sonicmaster/ui/tap_tempo_control.dart';

void main() {
  Future<List<int>> pump(
    WidgetTester tester, {
    int timeMin = 20,
    int timeMax = 1000,
    SonicMetrics metrics = SonicMetrics.regular,
  }) async {
    final sent = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SonicMetricsScope(
            metrics: metrics,
            child: TapTempoControl(
              timeMin: timeMin,
              timeMax: timeMax,
              currentMs: 500, // seeds bpm 120 at the default 1/4 division
              onSend: sent.add,
            ),
          ),
        ),
      ),
    );

    return sent;
  }

  // Dispose the tree so the periodic beat timer is cancelled (else the test
  // teardown reports a pending timer).
  Future<void> teardown(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  // Open the note-division dropdown (trigger shows the current label) and pick
  // [label] from the menu.
  Future<void> pickDivision(
    WidgetTester tester,
    String current,
    String label,
  ) async {
    await tester.tap(find.text(current));
    await tester.pump();
    await tester.tap(find.text(label).last);
    await tester.pump();
  }

  testWidgets('BPM submit sends the computed ms (120 bpm, 1/4 -> 500)', (
    tester,
  ) async {
    final sent = await pump(tester);

    await tester.enterText(find.byType(EditableText), '120');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();
    expect(sent.last, 500);
    await teardown(tester);
  });

  testWidgets('division change rescales (1/2 -> 1000)', (tester) async {
    final sent = await pump(tester);

    await pickDivision(tester, '1/4', '1/2');
    expect(sent.last, 1000);
    await teardown(tester);
  });

  testWidgets('out-of-range clamps the sent value and shows the clamped ms', (
    tester,
  ) async {
    final sent = await pump(tester, timeMax: 300);

    await pickDivision(tester, '1/4', '1/2'); // 120*2 = 1000 > 300
    expect(sent.last, 300); // clamped into range
    expect(find.text('300 ms'), findsOneWidget);
    await teardown(tester);
  });

  String bpmText(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).controller.text;

  testWidgets('compact: a decimal comma is accepted', (tester) async {
    final sent = await pump(tester, metrics: SonicMetrics.compact);

    await tester.enterText(find.byType(EditableText), '130,5');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();

    expect(sent, [460]); // round(60000 / 130.5)
    expect(bpmText(tester), '130.5');
    await teardown(tester);
  });

  testWidgets('regular: a decimal comma applies nothing (unchanged)', (
    tester,
  ) async {
    final sent = await pump(tester);

    await tester.enterText(find.byType(EditableText), '130,5');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();

    expect(sent, isEmpty);
    expect(bpmText(tester), '130,5');
    await teardown(tester);
  });

  testWidgets('compact: focusing the BPM well selects it, no suggestions', (
    tester,
  ) async {
    await pump(tester, metrics: SonicMetrics.compact);
    await tester.tap(find.byType(SonicField));
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText));

    expect(
      editable.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    expect(editable.autocorrect, isFalse);
    expect(editable.enableSuggestions, isFalse);
    await teardown(tester);
  });

  testWidgets('regular: the BPM well keeps today\'s entry options', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byType(SonicField));
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText));

    // Regular passes null: the platform default, which is a caret at the end
    // under flutter test's Android target (web and desktop select all).
    expect(
      editable.controller.selection,
      const TextSelection.collapsed(offset: 5),
    );
    expect(editable.autocorrect, isTrue);
    expect(editable.enableSuggestions, isTrue);
    await teardown(tester);
  });

  group('compact: the BPM well commits when it loses focus', () {
    testWidgets('a typed tempo commits on a tap outside', (tester) async {
      final sent = await pump(tester, metrics: SonicMetrics.compact);

      await tester.enterText(find.byType(EditableText), '130');
      await tester.tapAt(const Offset(5, 5)); // outside the BPM well
      await tester.pump();

      expect(sent, [462]); // round(60000 / 130) at the 1/4 division
      expect(bpmText(tester), '130.0');
      await teardown(tester);
    });

    testWidgets('Done, then a tap outside, sends once', (tester) async {
      final sent = await pump(tester, metrics: SonicMetrics.compact);

      await tester.enterText(find.byType(EditableText), '130');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump();
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();

      expect(sent, [462]);
      await teardown(tester);
    });

    testWidgets('text that is not a number reverts', (tester) async {
      final sent = await pump(tester, metrics: SonicMetrics.compact);

      await tester.enterText(find.byType(EditableText), 'abc');
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();

      expect(sent, isEmpty);
      expect(bpmText(tester), '120.0');
      await teardown(tester);
    });
  });

  testWidgets('regular: a click outside applies nothing (unchanged)', (
    tester,
  ) async {
    final sent = await pump(tester);

    await tester.enterText(find.byType(EditableText), '130');
    await tester.tapAt(const Offset(5, 5), kind: .mouse); // a desktop click
    await tester.pump();

    expect(sent, isEmpty);
    expect(bpmText(tester), '130'); // typed, not applied: only Done applies
    await teardown(tester);
  });
}
