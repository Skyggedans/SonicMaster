import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/mobile_screen.dart';
import 'package:sonicmaster/ui/fullscreen_button.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

import '../support/fake_mobile_screen.dart';

Future<void> pumpButton(
  WidgetTester tester,
  FakeMobileScreen screen, {
  SonicMetrics metrics = SonicMetrics.compact,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [mobileScreenProvider.overrideWithValue(screen)],
    child: Directionality(
      textDirection: .ltr,
      child: SonicMetricsScope(
        metrics: metrics,
        child: const Center(child: FullscreenButton()),
      ),
    ),
  ),
);

void main() {
  testWidgets('hidden on a desktop browser', (tester) async {
    // Desktop Chrome can go fullscreen: only the touch gate hides the button.
    await pumpButton(
      tester,
      FakeMobileScreen(
        isTouchBrowser: false,
        isPhoneScreen: false,
        isLandscapeLockSupported: false,
      ),
    );

    expect(find.byType(SonicIconButton), findsNothing);
  });

  testWidgets('hidden where the browser cannot go fullscreen', (tester) async {
    // iPhone (no element fullscreen) or an app installed fullscreen.
    await pumpButton(tester, FakeMobileScreen(isFullscreenAvailable: false));

    expect(find.byType(SonicIconButton), findsNothing);
  });

  testWidgets('a compact tablet gets it too, lock or not', (tester) async {
    // An iPad in portrait: compact layout, fullscreen but no landscape lock.
    await pumpButton(
      tester,
      FakeMobileScreen(isPhoneScreen: false, isLandscapeLockSupported: false),
    );

    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
  });

  testWidgets('not fullscreen: the enter icon, and a tap enters', (
    tester,
  ) async {
    final screen = FakeMobileScreen();

    await pumpButton(tester, screen);

    expect(find.byIcon(Icons.fullscreen), findsOneWidget);

    await tester.tap(find.byType(FullscreenButton));

    expect(screen.enterCount, 1);
    expect(screen.exitCount, 0);
  });

  testWidgets('fullscreen: the exit icon, and a tap leaves', (tester) async {
    final screen = FakeMobileScreen(isFullscreen: true);

    await pumpButton(tester, screen);

    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

    await tester.tap(find.byType(FullscreenButton));

    expect(screen.exitCount, 1);
    expect(screen.enterCount, 0);
  });

  testWidgets('follows fullscreen changes from outside', (tester) async {
    final screen = FakeMobileScreen();

    await pumpButton(tester, screen);
    screen.simulateFullscreenChange(isFullscreen: true); // granted
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

    screen.simulateFullscreenChange(isFullscreen: false); // Back, a picker
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fullscreen), findsOneWidget);

    await tester.tap(find.byType(FullscreenButton));

    expect(screen.enterCount, 1);
    expect(screen.exitCount, 0);
  });

  testWidgets(
    'a refused request keeps the enter icon; the next tap asks again',
    (tester) async {
      // Samsung Internet or Firefox may refuse: nothing changes, no event.
      final screen = FakeMobileScreen();

      await pumpButton(tester, screen);
      await tester.tap(find.byType(FullscreenButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.fullscreen), findsOneWidget);

      await tester.tap(find.byType(FullscreenButton));

      expect(screen.enterCount, 2);
      expect(screen.exitCount, 0);
    },
  );

  testWidgets('sized like the title-bar icons of each layout', (tester) async {
    await pumpButton(tester, FakeMobileScreen());

    expect(tester.getSize(find.byType(FullscreenButton)), const Size(38, 46));

    await pumpButton(tester, FakeMobileScreen(), metrics: SonicMetrics.regular);

    expect(tester.getSize(find.byType(FullscreenButton)), const Size(38, 38));
  });

  testWidgets('screen readers hear a button named for what it does', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final screen = FakeMobileScreen();

    await pumpButton(tester, screen);

    expect(find.bySemanticsLabel('Fullscreen'), findsOneWidget);

    screen.simulateFullscreenChange(isFullscreen: true);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Exit fullscreen'), findsOneWidget);

    semantics.dispose();
  });
}
