import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/preset_browser_page.dart';

import '../support/page_harness.dart';

/// Characterization goldens of the regular (desktop / tablet) layout, captured
/// before the compact work touched any layout code. Every later change must
/// keep them pixel-identical. Regenerate them only for an intentional
/// regular-layout change, and then in CI's environment (ubuntu-latest) —
/// never to absorb an unexplained diff.
void main() {
  testWidgets('regular layout, connected', (tester) async {
    await pumpPage(tester, size: const Size(1280, 800));
    await _settleSvgs(tester);

    await expectLater(
      find.byType(PresetBrowserPage),
      matchesGoldenFile('goldens/page_regular_1280x800.png'),
    );
  });

  testWidgets('regular layout, disconnected', (tester) async {
    await pumpPage(tester, size: const Size(1280, 800), isConnected: false);
    await _settleSvgs(tester);

    await expectLater(
      find.byType(PresetBrowserPage),
      matchesGoldenFile('goldens/page_regular_disconnected_1280x800.png'),
    );
  });
}

/// Settles the page, then checks that every SVG (the logo, the chain icons)
/// has decoded — a decoded picture sits in a FittedBox, an undecoded one is an
/// empty SizedBox — so a golden can never capture blank icons.
Future<void> _settleSvgs(WidgetTester tester) async {
  await tester.pumpAndSettle();

  final svgs = find.byType(SvgPicture);

  expect(svgs, findsWidgets);
  expect(
    find.descendant(of: svgs, matching: find.byType(FittedBox)),
    findsNWidgets(svgs.evaluate().length),
  );
}
