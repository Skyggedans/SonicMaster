import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/mobile_screen.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/rotate_device_overlay.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

import '../support/fake_mobile_screen.dart';
import '../support/fonts.dart';
import '../support/view_helpers.dart';

const portrait = Size(390, 844);
const landscape = Size(844, 390);
const prompt = 'Rotate your device to landscape';

/// A WidgetsApp with the overlay where SonicMasterApp's frame puts it: under
/// the metrics scope, around the Navigator.
Future<void> pumpApp(
  WidgetTester tester,
  FakeMobileScreen screen, {
  required Size size,
  required Widget home,
}) async {
  await loadOswald();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [mobileScreenProvider.overrideWithValue(screen)],
      child: WidgetsApp(
        color: const Color(0xFF000000),
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
            PageRouteBuilder<T>(
              settings: settings,
              pageBuilder: (context, _, _) => builder(context),
            ),
        builder: (context, child) => SonicMetricsScope(
          metrics: SonicMetrics.forSize(MediaQuery.sizeOf(context)),
          child: RotateDeviceOverlay(child: child!),
        ),
        home: home,
      ),
    ),
  );
}

Future<void> turn(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump();
}

/// The FocusScope WidgetsApp wraps around its Navigator: the builder's child.
Element navigatorScope(WidgetTester tester) => tester.element(
  find
      .ancestor(of: find.byType(Navigator), matching: find.byType(FocusScope))
      .first,
);

/// Stands in for the app: a full-screen tap target that counts taps.
class _TapCounter extends HookWidget {
  const _TapCounter();

  @override
  Widget build(BuildContext context) {
    final taps = useState(0);

    return GestureDetector(
      behavior: .opaque,
      onTap: () => taps.value++,
      child: Center(child: Text('taps ${taps.value}')),
    );
  }
}

/// A knob whose value lives in hook state, like a module parameter.
class _KnobHost extends HookWidget {
  const _KnobHost({required this.changes});

  final List<num> changes;

  @override
  Widget build(BuildContext context) {
    final value = useState<num>(50);

    return Center(
      child: KnobControl(
        value: value.value,
        min: 0,
        max: 100,
        step: 1,
        label: 'Level',
        size: 72,
        onChanged: (v) {
          changes.add(v);
          value.value = v;
        },
      ),
    );
  }
}

void main() {
  testWidgets(
    'a phone in portrait: the prompt covers the app and takes its taps',
    (tester) async {
      await pumpApp(
        tester,
        FakeMobileScreen(),
        size: portrait,
        home: const _TapCounter(),
      );

      expect(find.text(prompt), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pump();

      expect(find.text('taps 0'), findsOneWidget);
    },
  );

  testWidgets('a phone in landscape: no prompt, the app takes taps', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMobileScreen(),
      size: landscape,
      home: const _TapCounter(),
    );

    expect(find.text(prompt), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    expect(find.text('taps 1'), findsOneWidget);
  });

  testWidgets('turning the phone keeps the app mounted underneath', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMobileScreen(),
      size: landscape,
      home: const _TapCounter(),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    final scope = navigatorScope(tester);

    await turn(tester, portrait);

    expect(find.text(prompt), findsOneWidget);
    expect(navigatorScope(tester), same(scope));

    await turn(tester, landscape);

    expect(find.text(prompt), findsNothing);
    expect(navigatorScope(tester), same(scope));
    expect(find.text('taps 1'), findsOneWidget);
  });

  testWidgets(
    'a tablet in portrait gets no prompt (the compact layout instead)',
    (tester) async {
      await pumpApp(
        tester,
        FakeMobileScreen(isPhoneScreen: false),
        size: const Size(800, 1280),
        home: const _TapCounter(),
      );

      expect(find.text(prompt), findsNothing);
      expect(
        find.descendant(
          of: find.byType(RotateDeviceOverlay),
          matching: find.byType(ExcludeFocus),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('a desktop browser never shows it, even in a portrait window', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMobileScreen(
        isTouchBrowser: false,
        // A HiDPI laptop screen can read as phone-sized (under 600 logical
        // px): only the touch gate keeps the prompt off a desktop.
        isPhoneScreen: true,
        isFullscreenAvailable: false,
        isLandscapeLockSupported: false,
      ),
      size: const Size(700, 900),
      home: const _TapCounter(),
    );

    expect(find.text(prompt), findsNothing);
    expect(
      find.descendant(
        of: find.byType(RotateDeviceOverlay),
        matching: find.byType(ExcludeFocus),
      ),
      findsNothing,
    );

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    expect(find.text('taps 1'), findsOneWidget);
  });

  testWidgets('Fullscreen enters landscape fullscreen', (tester) async {
    final screen = FakeMobileScreen();

    await pumpApp(
      tester,
      screen,
      size: portrait,
      home: const SizedBox.expand(),
    );
    await tester.tap(find.text('Fullscreen'));
    await tester.pump();

    expect(screen.enterCount, 1);
    expect(find.textContaining('rotation lock'), findsNothing);
  });

  testWidgets('no Fullscreen button without the landscape lock (iOS, iPadOS)', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMobileScreen(isLandscapeLockSupported: false),
      size: portrait,
      home: const SizedBox.expand(),
    );

    expect(find.text(prompt), findsOneWidget);
    expect(find.text('Fullscreen'), findsNothing);
    expect(find.textContaining('auto-rotate'), findsNothing);
    expect(find.textContaining('rotation lock'), findsOneWidget);
  });

  testWidgets('no Fullscreen button where fullscreen is unavailable', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMobileScreen(isFullscreenAvailable: false),
      size: portrait,
      home: const SizedBox.expand(),
    );

    expect(find.text(prompt), findsOneWidget);
    expect(find.text('Fullscreen'), findsNothing);
    expect(find.textContaining('rotation lock'), findsOneWidget);
  });

  for (final size in const [Size(300, 420), Size(320, 480)]) {
    testWidgets('fits a ${size.width.toInt()}x${size.height.toInt()} window', (
      tester,
    ) async {
      await pumpApp(
        tester,
        FakeMobileScreen(),
        size: size,
        home: const SizedBox.expand(),
      );

      expectNoOverflow(tester);

      await tester.ensureVisible(find.text('Fullscreen'));
      await tester.pumpAndSettle();

      expectWithin(
        tester.getRect(find.text('Fullscreen')),
        Offset.zero & size,
        'Fullscreen',
      );
    });
  }

  testWidgets(
    'the hidden app loses keyboard focus and takes it again in landscape',
    (tester) async {
      final node = FocusNode();

      addTearDown(node.dispose);
      await pumpApp(
        tester,
        FakeMobileScreen(),
        size: landscape,
        home: Focus(focusNode: node, child: const SizedBox.expand()),
      );
      node.requestFocus();
      await tester.pump();

      expect(node.hasFocus, isTrue);

      await turn(tester, portrait);

      expect(node.hasFocus, isFalse);

      node.requestFocus();
      await tester.pump();

      expect(node.hasFocus, isFalse); // nothing under the prompt can take it

      await turn(tester, landscape);
      node.requestFocus();
      await tester.pump();

      expect(node.hasFocus, isTrue);
    },
  );

  testWidgets('the prompt covers an open dialog too', (tester) async {
    late BuildContext routeContext;

    await pumpApp(
      tester,
      FakeMobileScreen(),
      size: landscape,
      home: Builder(
        builder: (context) {
          routeContext = context;

          return const SizedBox.expand();
        },
      ),
    );
    unawaited(
      showSonicDialog<void>(
        context: routeContext,
        builder: (_) => SonicDialog(
          child: SonicButton(label: 'Keep', onPressed: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Keep').hitTestable(), findsOneWidget);

    await turn(tester, portrait);

    expect(find.text('Keep'), findsOneWidget); // still open underneath
    expect(find.text('Keep').hitTestable(), findsNothing);
    expect(find.text(prompt).hitTestable(), findsOneWidget);
  });

  testWidgets('screen readers get only the prompt', (tester) async {
    final semantics = tester.ensureSemantics();

    await pumpApp(
      tester,
      FakeMobileScreen(),
      size: landscape,
      home: Semantics(label: 'the app', child: const SizedBox.expand()),
    );

    expect(find.semantics.byLabel('the app'), findsOne);

    await turn(tester, portrait);

    expect(find.semantics.byLabel('the app'), findsNothing);
    expect(find.semantics.byLabel(prompt), findsOne);

    semantics.dispose();
  });

  testWidgets('a knob value being typed when the phone turns is committed', (
    tester,
  ) async {
    final changes = <num>[];

    await pumpApp(
      tester,
      FakeMobileScreen(),
      size: landscape,
      home: _KnobHost(changes: changes),
    );

    final readout = tester.getCenter(find.text('50'));

    await tester.tapAt(readout);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(readout);
    await tester.pump();
    await tester.enterText(find.byType(EditableText), '77');
    await turn(tester, portrait);
    await tester.pump();

    expect(changes, [77]);
    expect(find.byType(EditableText), findsNothing);

    await turn(tester, landscape);

    expect(find.text('77'), findsOneWidget);

    // Flush the DoubleTapGestureRecognizer's kDoubleTapMinTime timer.
    await tester.pump(const Duration(milliseconds: 50));
  });
}
