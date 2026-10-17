import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'view_helpers.dart';

void main() {
  test('expectWithin accepts touching edges and rejects a spill', () {
    const area = Rect.fromLTWH(0, 0, 852, 213);

    expectWithin(const Rect.fromLTWH(0, 173, 852, 40), area, 'flush');
    expect(
      () => expectWithin(const Rect.fromLTWH(0, 174, 852, 40), area, 'spill'),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('expectNoOverflow catches an overflowing frame', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: .ltr,
        child: Row(children: [SizedBox(width: 100000)]),
      ),
    );

    expect(() => expectNoOverflow(tester), throwsA(isA<TestFailure>()));

    await tester.pumpWidget(const SizedBox.shrink());

    expectNoOverflow(tester);
  });

  testWidgets('expectNoOverflow fails on a non-overflow error too', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: Builder(builder: (_) => throw StateError('boom')),
      ),
    );

    expect(() => expectNoOverflow(tester), throwsA(isA<TestFailure>()));
  });

  testWidgets('setKeyboard insets the view in logical px, size unchanged', (
    tester,
  ) async {
    late EdgeInsets insets;
    late Size size;

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          insets = MediaQuery.viewInsetsOf(context);
          size = MediaQuery.sizeOf(context);

          return const SizedBox.shrink();
        },
      ),
    );

    final viewSize = size;

    await setKeyboard(tester, 180);

    expect(insets.bottom, 180);
    expect(size, viewSize);

    await setKeyboard(tester, 0);

    expect(insets.bottom, 0);
  });

  testWidgets('simulateSystemBack pops the top route, then leaves the app', (
    tester,
  ) async {
    final calls = <String>[];

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);

        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      WidgetsApp(
        navigatorKey: navigatorKey,
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
        home: const Text('home'),
      ),
    );
    unawaited(
      navigatorKey.currentState!.push(
        PageRouteBuilder<void>(pageBuilder: (_, _, _) => const Text('second')),
      ),
    );
    await tester.pumpAndSettle();
    await simulateSystemBack(tester);
    await tester.pumpAndSettle();

    expect(find.text('second'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(calls, isNot(contains('SystemNavigator.pop')));

    await simulateSystemBack(tester);

    expect(calls, contains('SystemNavigator.pop'));
  });
}
