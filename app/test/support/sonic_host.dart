import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/main.dart';

import 'fonts.dart';

/// Pumps [home] as the first route of the real app shell ([SonicMasterApp]:
/// its WidgetsApp, routes, default text style and frame, so the
/// SonicMetricsScope too) under a ProviderScope with [overrides], at [size]
/// logical px (dpr 1) with a simulated soft keyboard [keyboard] px tall, and
/// Oswald loaded.
///
/// Returns a context below the Navigator: hand it to showSonicDialog and the
/// other show* entry points. For the whole page use pumpPage instead.
Future<BuildContext> pumpSonicHost(
  WidgetTester tester, {
  Widget home = const SizedBox.shrink(),
  Size size = const Size(1280, 800),
  double keyboard = 0,
  List<Override> overrides = const [],
}) async {
  await loadOswald();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);

  late BuildContext routeContext;

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: SonicMasterApp(
        home: Builder(
          builder: (context) {
            routeContext = context;

            return home;
          },
        ),
      ),
    ),
  );

  return routeContext;
}
