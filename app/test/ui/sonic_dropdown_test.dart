import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/edit_providers.dart';
import 'package:sonicmaster/state/layout_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/save_preset_dialog.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

import '../support/page_harness.dart';
import '../support/sonic_host.dart';
import '../support/view_helpers.dart';

void main() {
  group('placeDropdownMenu', () {
    test('opens below with the 300-px cap when there is room', () {
      final placement = placeDropdownMenu(
        trigger: const Rect.fromLTWH(100, 100, 110, 40),
        screen: const Size(1280, 800),
        bottomInset: 0,
        menuWidth: 110,
        contentHeight: 2000,
      );

      expect(placement, (isAbove: false, maxHeight: 300.0, dx: 0.0));
    });

    test('a short list that fits below keeps today\'s placement', () {
      final placement = placeDropdownMenu(
        trigger: const Rect.fromLTWH(100, 200, 110, 40),
        screen: const Size(568, 320),
        bottomInset: 0,
        menuWidth: 110,
        contentHeight: 40,
      );

      // 320 - 8 - 6 - 240 = 66 below; 66 - 14 = 52 >= 40, so the list fits.
      expect(placement, (isAbove: false, maxHeight: 52.0, dx: 0.0));
    });

    test('flips above when the space below is short', () {
      final placement = placeDropdownMenu(
        trigger: const Rect.fromLTWH(100, 260, 110, 40),
        screen: const Size(568, 320),
        bottomInset: 0,
        menuWidth: 110,
        contentHeight: 2000,
      );

      expect(placement.isAbove, isTrue);
      expect(placement.maxHeight, 260 - 6 - 8 - 14);
    });

    test('caps the list to the room left above the soft keyboard', () {
      final placement = placeDropdownMenu(
        trigger: const Rect.fromLTWH(100, 80, 110, 40),
        screen: const Size(852, 393),
        bottomInset: 180,
        menuWidth: 110,
        contentHeight: 2000,
      );

      expect(placement.isAbove, isFalse); // 79 px below beats 66 above
      expect(placement.maxHeight, 393 - 180 - 8 - 6 - 120 - 14);
    });

    test('shifts left to stay on screen', () {
      final placement = placeDropdownMenu(
        trigger: const Rect.fromLTWH(500, 100, 60, 40),
        screen: const Size(568, 320),
        bottomInset: 0,
        menuWidth: 200,
        contentHeight: 100,
      );

      expect(placement.dx, 568 - 8 - 200 - 500);
    });

    test('shifts right off the left edge', () {
      final placement = placeDropdownMenu(
        trigger: const Rect.fromLTWH(2, 100, 60, 40),
        screen: const Size(568, 320),
        bottomInset: 0,
        menuWidth: 100,
        contentHeight: 100,
      );

      expect(placement.dx, 6);
    });
  });

  group('the Save dialog\'s Slot menu', () {
    const current = PresetRef(.user, 5);

    Future<void> openSave(
      WidgetTester tester, {
      required Size size,
      double keyboard = 0,
    }) async {
      final context = await pumpSonicHost(
        tester,
        size: size,
        keyboard: keyboard,
        overrides: [
          currentPresetProvider.overrideWith((_) => current),
          presetNamesProvider.overrideWith((_) => {current: 'MyPatch'}),
          dataAssetsProvider.overrideWith(
            (_) => Completer<DataAssets>().future,
          ),
        ],
      );

      unawaited(showSavePresetDialog(context));
      await tester.pumpAndSettle();
      await tester.tap(find.text('P05'));
      await tester.pumpAndSettle();
    }

    Rect trigger(WidgetTester tester) =>
        tester.getRect(find.byType(SonicDropdown<int>));

    // The menu's plate: the SonicSurface closest around a menu row (the
    // dialog's plate is an ancestor too: the menu lives in its OverlayPortal).
    Rect menu(WidgetTester tester) => tester.getRect(
      find
          .ancestor(of: find.text('P06'), matching: find.byType(SonicSurface))
          .first,
    );

    // On screen (above the keyboard) and attached to its trigger: 6 px below
    // it, or 6 px above it.
    void expectPlaced(WidgetTester tester, Rect visible) {
      final (menuRect, triggerRect) = (menu(tester), trigger(tester));

      expectWithin(menuRect, visible, 'the menu');
      expect(
        (menuRect.top - triggerRect.bottom - 6).abs() < 0.01 ||
            (triggerRect.top - menuRect.bottom - 6).abs() < 0.01,
        isTrue,
        reason: 'menu $menuRect is not attached to its trigger $triggerRect',
      );
    }

    testWidgets('568x320: it opens upward, fully on screen', (tester) async {
      await openSave(tester, size: const Size(568, 320));

      expect(menu(tester).bottom, lessThanOrEqualTo(trigger(tester).top));
      expectPlaced(tester, const Rect.fromLTWH(0, 0, 568, 320));
    });

    testWidgets('the keyboard closing under it: it stays open and follows', (
      tester,
    ) async {
      await openSave(tester, size: const Size(852, 393), keyboard: 180);
      expectPlaced(tester, const Rect.fromLTWH(0, 0, 852, 393 - 180));

      final before = trigger(tester);

      await setKeyboard(tester, 0); // the dialog re-centres: the trigger moves
      await tester.pumpAndSettle();

      expect(trigger(tester), isNot(before));
      expect(find.text('P06'), findsOneWidget); // still open
      expectPlaced(tester, const Rect.fromLTWH(0, 0, 852, 393));
    });

    // A phone turned to portrait and back while the Slot menu is open: the
    // menu must land on screen again, attached to the moved trigger, not keep
    // the placement it had for the portrait screen.
    testWidgets('turning the phone and back: it stays open and on screen', (
      tester,
    ) async {
      await openSave(tester, size: const Size(852, 393));

      tester.view.physicalSize = const Size(393, 852);
      await tester.pumpAndSettle();

      expect(find.text('P06'), findsOneWidget);
      expectPlaced(tester, const Rect.fromLTWH(0, 0, 393, 852));

      tester.view.physicalSize = const Size(852, 393);
      await tester.pumpAndSettle();

      expect(find.text('P06'), findsOneWidget);
      expectPlaced(tester, const Rect.fromLTWH(0, 0, 852, 393));
    });

    testWidgets('compact: Back closes the menu, then the dialog', (
      tester,
    ) async {
      await openSave(tester, size: const Size(852, 393));
      await simulateSystemBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('P06'), findsNothing); // the menu closed
      expect(find.text('Save preset'), findsOneWidget); // the dialog stayed

      await simulateSystemBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('Save preset'), findsNothing);
    });

    testWidgets('regular: Escape still closes the dialog with its menu', (
      tester,
    ) async {
      await openSave(tester, size: const Size(1280, 800));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('P06'), findsNothing);
      expect(find.text('Save preset'), findsNothing);
    });
  });

  testWidgets('compact page: Back closes a work-area menu, nothing else', (
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

    // FX1 holds COMP 1: its effect menu lists COMP 2 among others.
    final container = await pumpPage(
      tester,
      size: const Size(852, 393),
      selectedEffects: const {1: 101},
      parameters: const {1: {}},
      overrides: [selectedModuleProvider.overrideWith((_) => 1)],
    );

    await tester.tap(
      find.descendant(
        of: find.byType(SonicDropdown<int>),
        matching: find.text('COMP 1'),
      ),
    );
    await tester.pump();

    expect(find.text('COMP 2'), findsOneWidget);

    await simulateSystemBack(tester);
    await tester.pump();

    expect(find.text('COMP 2'), findsNothing);
    expect(container.read(presetDrawerOpenProvider), isFalse);
    expect(calls, isNot(contains('SystemNavigator.pop'))); // the app stays
  });
}
