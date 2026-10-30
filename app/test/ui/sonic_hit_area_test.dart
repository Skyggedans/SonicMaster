import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

void main() {
  // A 100x60 parent target holding a SonicHitArea whose 10-px padding rings a
  // 20x20 inner target.
  Future<({List<String> taps})> pumpHitArea(
    WidgetTester tester, {
    required bool isActive,
  }) async {
    final taps = <String>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: Center(
          child: GestureDetector(
            onTap: () => taps.add('parent'),
            child: Container(
              width: 100,
              height: 60,
              color: const Color(0xFF000000),
              alignment: .center,
              child: SonicHitArea(
                padding: const EdgeInsets.all(10),
                onTap: isActive ? () => taps.add('area') : null,
                child: GestureDetector(
                  key: const Key('inner'),
                  behavior: .opaque,
                  onTap: () => taps.add('inner'),
                  child: const SizedBox.square(dimension: 20),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return (taps: taps);
  }

  Offset besideInner(WidgetTester tester) =>
      tester.getRect(find.byKey(const Key('inner'))).topCenter -
      const Offset(0, 5);

  testWidgets('its padding takes taps meant for the inner target', (
    tester,
  ) async {
    final (:taps) = await pumpHitArea(tester, isActive: true);

    await tester.tapAt(besideInner(tester));

    expect(taps, ['area']);
  });

  testWidgets('the inner target still wins its own taps', (tester) async {
    final (:taps) = await pumpHitArea(tester, isActive: true);

    await tester.tap(find.byKey(const Key('inner')));

    expect(taps, ['inner']);
  });

  testWidgets('without onTap the space is inert: taps reach the parent', (
    tester,
  ) async {
    final (:taps) = await pumpHitArea(tester, isActive: false);

    await tester.tapAt(besideInner(tester));

    expect(taps, ['parent']);
  });
}
