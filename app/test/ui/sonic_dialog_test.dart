import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

import '../support/sonic_host.dart';
import '../support/view_helpers.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Widget dialog, {
    Size size = const Size(1280, 800),
    double keyboard = 0,
  }) async {
    final context = await pumpSonicHost(tester, size: size, keyboard: keyboard);

    unawaited(showSonicDialog<void>(context: context, builder: (_) => dialog));
    await tester.pumpAndSettle();
  }

  Rect plate(WidgetTester tester) => tester.getRect(find.byType(SonicSurface));

  test('dialog tokens: regular is today\'s literals, compact is tighter', () {
    expect(
      SonicMetrics.regular.dialogMargin,
      const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
    );
    expect(
      SonicMetrics.regular.dialogPadding,
      const EdgeInsets.fromLTRB(24, 22, 24, 18),
    );
    expect(
      SonicMetrics.compact.dialogMargin,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
    expect(
      SonicMetrics.compact.dialogPadding,
      const EdgeInsets.fromLTRB(16, 12, 16, 10),
    );
  });

  testWidgets('regular: a dialog that fits keeps its exact geometry', (
    tester,
  ) async {
    await open(
      tester,
      const SonicDialog(child: SizedBox(width: 600, height: 100)),
    );

    // maxWidth 460, centred; 100 + padding 22 + 18 + a 1-px border each side.
    expect(plate(tester), const Rect.fromLTWH(410, 329, 460, 142));
  });

  testWidgets('regular: the soft keyboard does not move the plate', (
    tester,
  ) async {
    await open(
      tester,
      const SonicDialog(child: SizedBox(width: 600, height: 100)),
      keyboard: 300, // a tablet in landscape typing
    );

    expect(plate(tester), const Rect.fromLTWH(410, 329, 460, 142));
  });

  testWidgets('compact: tighter margin and padding', (tester) async {
    await open(
      tester,
      const SonicDialog(
        maxWidth: 600,
        child: SizedBox(width: 2000, height: 50),
      ),
      size: const Size(568, 320),
    );

    // 568 - 2 x 16 margin = 536 wide; 50 + 12 + 10 + 2 x 1 border tall.
    expect(plate(tester), const Rect.fromLTWH(16, 123, 536, 74));
  });

  testWidgets('an explicit padding still wins over the token', (tester) async {
    await open(
      tester,
      const SonicDialog(
        padding: EdgeInsets.all(20),
        child: SizedBox(height: 50),
      ),
      size: const Size(568, 320),
    );

    expect(plate(tester).height, 50 + 40 + 2);
  });

  testWidgets('compact: the plate sits in the space above the keyboard', (
    tester,
  ) async {
    await open(
      tester,
      const SonicDialog(child: SizedBox(height: 120)),
      size: const Size(852, 393),
      keyboard: 180,
    );

    expectWithin(
      plate(tester),
      const Rect.fromLTWH(0, 0, 852, 393 - 180),
      'the plate',
    );
  });

  testWidgets('compact: a keyboard raised after opening lifts the plate', (
    tester,
  ) async {
    await open(
      tester,
      const SonicDialog(child: SizedBox(height: 120)),
      size: const Size(852, 393),
    );
    await setKeyboard(tester, 180);
    await tester.pump();

    expectWithin(
      plate(tester),
      const Rect.fromLTWH(0, 0, 852, 393 - 180),
      'the plate',
    );
  });

  testWidgets('taller content scrolls inside the plate', (tester) async {
    await open(
      tester,
      SonicDialog(
        child: Column(
          mainAxisSize: .min,
          children: [
            for (final i in Iterable<int>.generate(20))
              SizedBox(height: 40, child: Text('row $i')),
          ],
        ),
      ),
      size: const Size(568, 320),
    );

    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('row 19'));
    await tester.pumpAndSettle();

    expectWithin(
      tester.getRect(find.text('row 19')),
      const Rect.fromLTWH(0, 0, 568, 320),
      'the last row',
    );
  });

  testWidgets('isScrollable false bounds the child for its Flexible parts', (
    tester,
  ) async {
    await open(
      tester,
      const SonicDialog(
        isScrollable: false,
        child: Column(
          mainAxisSize: .min,
          children: [
            Flexible(child: SizedBox(height: 1000)),
            Text('pinned'),
          ],
        ),
      ),
      size: const Size(568, 320),
    );

    expect(tester.takeException(), isNull);
    expectWithin(
      tester.getRect(find.text('pinned')),
      const Rect.fromLTWH(0, 0, 568, 320),
      'the pinned row',
    );
  });

  testWidgets('a knob in a dialog that scrolls still turns on a touch drag', (
    tester,
  ) async {
    final changed = <num>[];

    await open(
      tester,
      SonicDialog(
        child: Column(
          mainAxisSize: .min,
          children: [
            KnobControl(
              value: 50,
              min: 0,
              max: 100,
              step: 1,
              label: 'X',
              size: 72,
              onChanged: changed.add,
            ),
            const SizedBox(height: 600),
          ],
        ),
      ),
      size: const Size(568, 320),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('knob'))),
    );

    for (final _ in Iterable<int>.generate(6)) {
      await gesture.moveBy(const Offset(0, -10));
    }

    await gesture.up();
    await tester.pump();

    expect(changed.last, greaterThan(50));
  });
}
