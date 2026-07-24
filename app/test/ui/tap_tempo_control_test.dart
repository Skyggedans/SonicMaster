import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/tap_tempo_control.dart';

void main() {
  Future<List<int>> pump(
    WidgetTester tester, {
    int timeMin = 20,
    int timeMax = 1000,
  }) async {
    final sent = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TapTempoControl(
            timeMin: timeMin,
            timeMax: timeMax,
            currentMs: 500, // seeds bpm 120 at the default 1/4 division
            onSend: sent.add,
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
}
