import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/global_settings.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/global_settings_dialog.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/preset_drawer.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

import '../support/page_harness.dart';
import '../support/sonic_host.dart';
import '../support/test_assets.dart';

/// How a knob shares pointer input with the scroll views around it: touch
/// drags turn it (hold-to-turn knobs wait 200 ms first), mouse drags turn it at
/// once, trackpad swipes and drags beside it scroll, and a wheel tick only
/// nudges it.
void main() {
  // A knob at the start of a scroll view whose content is far longer than the
  // viewport, so the scroll view's own drag recognizer competes for every drag
  // along [axis].
  Future<(List<num>, ScrollController)> pumpInScroll(
    WidgetTester tester, {
    Axis axis = .vertical,
    bool isHoldToTurnOnTouch = false,
  }) async {
    final changed = <num>[];
    final controller = ScrollController();

    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            scrollDirection: axis,
            child: Flex(
              direction: axis,
              crossAxisAlignment: .start,
              children: [
                KnobControl(
                  value: 50,
                  min: 0,
                  max: 100,
                  step: 1,
                  label: 'X',
                  isHoldToTurnOnTouch: isHoldToTurnOnTouch,
                  onChanged: changed.add,
                ),
                const SizedBox.square(dimension: 2000),
              ],
            ),
          ),
        ),
      ),
    );

    return (changed, controller);
  }

  // Six moves of [step] from [from], released at once: a real flick. The
  // second move crosses the 18-px touch slop.
  Future<void> dragFrom(
    WidgetTester tester,
    Offset from,
    Offset step, {
    PointerDeviceKind kind = .touch,
    Duration hold = Duration.zero,
  }) async {
    final gesture = await tester.startGesture(from, kind: kind);

    if (hold > Duration.zero) await tester.pump(hold);

    for (final _ in Iterable<int>.generate(6)) {
      await gesture.moveBy(step);
    }

    await gesture.up();
    await tester.pump();
  }

  Offset knobCenter(WidgetTester tester) =>
      tester.getCenter(find.byKey(const Key('knob')));

  group('touch', () {
    testWidgets('a drag on a knob inside a vertical scroll turns the knob', (
      tester,
    ) async {
      final (changed, controller) = await pumpInScroll(tester);

      await dragFrom(tester, knobCenter(tester), const Offset(0, -10));

      expect(changed, isNotEmpty);
      expect(changed.last, greaterThan(50));
      expect(controller.offset, 0); // the scroll view lost the arena
    });

    testWidgets('a drag beside the knob still scrolls', (tester) async {
      final (changed, controller) = await pumpInScroll(tester);

      await dragFrom(tester, const Offset(400, 400), const Offset(0, -10));

      expect(changed, isEmpty);
      expect(controller.offset, greaterThan(0));
    });

    testWidgets('a vertical drag in a horizontal scroll turns the knob', (
      tester,
    ) async {
      final (changed, controller) = await pumpInScroll(
        tester,
        axis: .horizontal,
      );

      await dragFrom(tester, knobCenter(tester), const Offset(0, -10));

      expect(changed.last, greaterThan(50));
      expect(controller.offset, 0);
    });

    testWidgets('a sideways drag on a knob scrolls the horizontal view', (
      tester,
    ) async {
      final (changed, controller) = await pumpInScroll(
        tester,
        axis: .horizontal,
      );

      await dragFrom(tester, knobCenter(tester), const Offset(-10, 0));

      expect(changed, isEmpty);
      expect(controller.offset, greaterThan(0));
    });
  });

  group('hold-to-turn on touch', () {
    testWidgets('a quick flick across the knob scrolls the list', (
      tester,
    ) async {
      final (changed, controller) = await pumpInScroll(
        tester,
        isHoldToTurnOnTouch: true,
      );

      await dragFrom(tester, knobCenter(tester), const Offset(0, -10));

      expect(changed, isEmpty);
      expect(controller.offset, greaterThan(0));
    });

    testWidgets('a 250-ms hold, then a drag, turns the knob', (tester) async {
      final (changed, controller) = await pumpInScroll(
        tester,
        isHoldToTurnOnTouch: true,
      );

      await dragFrom(
        tester,
        knobCenter(tester),
        const Offset(0, -10),
        hold: const Duration(milliseconds: 250),
      );

      expect(changed.last, greaterThan(50));
      expect(controller.offset, 0);
    });

    // A resting finger drifts a little (up to the touch slop) before the hold
    // arms. The drift is no turn: the first move after the hold only sets
    // where the turn starts from.
    testWidgets('drift while holding does not jump the value', (tester) async {
      final (changed, _) = await pumpInScroll(
        tester,
        isHoldToTurnOnTouch: true,
      );

      final gesture = await tester.startGesture(knobCenter(tester));

      await gesture.moveBy(const Offset(0, 5));
      await gesture.moveBy(const Offset(0, 5));
      await tester.pump(const Duration(milliseconds: 250));
      await gesture.moveBy(const Offset(0, -1));

      expect(changed, isEmpty);

      await gesture.moveBy(const Offset(0, -10));

      expect(changed.last, greaterThan(50));

      await gesture.up();
      await tester.pump();
    });

    testWidgets('a mouse still turns it at once', (tester) async {
      final (changed, _) = await pumpInScroll(
        tester,
        isHoldToTurnOnTouch: true,
      );

      await dragFrom(
        tester,
        knobCenter(tester),
        const Offset(0, -10),
        kind: .mouse,
      );

      expect(changed.last, greaterThan(50));
    });
  });

  group('mouse, trackpad and wheel', () {
    testWidgets('a mouse drag turns the knob (unchanged)', (tester) async {
      final (changed, controller) = await pumpInScroll(tester);

      await dragFrom(
        tester,
        knobCenter(tester),
        const Offset(0, -10),
        kind: .mouse,
      );

      expect(changed.last, greaterThan(50));
      expect(controller.offset, 0);
    });

    testWidgets('a trackpad swipe over a knob scrolls the page '
        '(native pan-zoom, unchanged)', (tester) async {
      final (changed, controller) = await pumpInScroll(tester);
      final center = knobCenter(tester);
      final pointer = TestPointer(2, .trackpad);

      await tester.sendEventToBinding(pointer.panZoomStart(center));

      for (final step in Iterable<int>.generate(6, (i) => i + 1)) {
        await tester.sendEventToBinding(
          pointer.panZoomUpdate(center, pan: Offset(0, -10.0 * step)),
        );
      }

      await tester.sendEventToBinding(pointer.panZoomEnd());
      await tester.pump();

      expect(changed, isEmpty);
      expect(controller.offset, greaterThan(0));
    });

    // The web engine never sends pan-zoom: a two-finger swipe arrives as
    // scroll signals of kind trackpad. The knob may take a nudge or two before
    // it scrolls out from under the pointer, as before.
    testWidgets('a web trackpad swipe over a knob scrolls the page '
        '(unchanged)', (tester) async {
      final (changed, controller) = await pumpInScroll(tester);
      final center = knobCenter(tester);

      for (final _ in Iterable<int>.generate(6)) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: .trackpad,
            position: center,
            scrollDelta: const Offset(0, 20),
          ),
        );
        await tester.pump();
      }

      expect(controller.offset, greaterThan(0));
      expect(changed.length, lessThan(6));
    });

    testWidgets('a wheel tick over a knob nudges it once, the page stays', (
      tester,
    ) async {
      final (changed, controller) = await pumpInScroll(tester);

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: knobCenter(tester),
          scrollDelta: const Offset(0, 20),
        ),
      );
      await tester.pump();

      expect(changed, [49]);
      expect(controller.offset, 0);
    });
  });

  group('knobs inside scrolling lists hold to turn', () {
    Finder inDrawer(Finder finder) =>
        find.descendant(of: find.byType(PresetDrawer), matching: finder);

    // The drawer's one scroll list (its first Scrollable; the search field's
    // own is deeper).
    ScrollPosition drawerList(WidgetTester tester) => tester
        .state<ScrollableState>(inDrawer(find.byType(Scrollable)).first)
        .position;

    // Opens the drawer with its list at the top, Master Vol in view, whatever
    // the open-time reveal did.
    Future<void> openDrawer(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      drawerList(tester).jumpTo(0);
      await tester.pump();
    }

    testWidgets('a flick on the drawer\'s Master Vol scrolls the drawer', (
      tester,
    ) async {
      final container = await pumpPage(tester, size: const Size(852, 393));

      await openDrawer(tester);
      await dragFrom(
        tester,
        tester.getCenter(inDrawer(find.byKey(const Key('knob')))),
        const Offset(0, -10),
      );

      expect(drawerList(tester).pixels, greaterThan(0));
      expect(container.read(globalVolumeProvider), 75);
    });

    testWidgets('a hold, then a drag, turns the drawer\'s Master Vol', (
      tester,
    ) async {
      final container = await pumpPage(tester, size: const Size(852, 393));

      await openDrawer(tester);
      await dragFrom(
        tester,
        tester.getCenter(inDrawer(find.byKey(const Key('knob')))),
        const Offset(0, -10),
        hold: const Duration(milliseconds: 250),
      );

      expect(drawerList(tester).pixels, 0);
      expect(container.read(globalVolumeProvider), greaterThan(75));
    });

    testWidgets('the Settings level and backlight knobs hold to turn', (
      tester,
    ) async {
      final context = await pumpSonicHost(
        tester,
        overrides: [
          dataAssetsProvider.overrideWith((_) => loadTestDataAssets()),
          globalSettingsProvider.overrideWith(
            (_) => const GlobalSettings(
              globalVolume: 50,
              inputLevel: 0,
              fxRecLevel: 0,
              monitorLevel: 0,
              btRecLevel: 0,
            ),
          ),
        ],
      );

      showSonicDialog<void>(
        context: context,
        builder: (_) => const GlobalSettingsDialog(),
      );
      await tester.pumpAndSettle();

      final knobs = tester.widgetList<KnobControl>(
        find.descendant(
          of: find.byType(GlobalSettingsDialog),
          matching: find.byType(KnobControl),
        ),
      );

      expect(knobs, hasLength(5)); // four levels + backlight
      expect(knobs.every((knob) => knob.isHoldToTurnOnTouch), isTrue);
    });
  });
}
