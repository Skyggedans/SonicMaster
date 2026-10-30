import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/layout_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/theme/app_colors.dart';
import 'package:sonicmaster/ui/chain_view.dart';
import 'package:sonicmaster/ui/global_settings_dialog.dart';
import 'package:sonicmaster/ui/preset_drawer.dart';
import 'package:sonicmaster/ui/preset_rail.dart';
import 'package:sonicmaster/ui/save_preset_dialog.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/top_bar.dart';

import '../support/page_harness.dart';
import '../support/silent_transport.dart';
import '../support/view_helpers.dart';

Finder _inDrawer(Finder finder) =>
    find.descendant(of: find.byType(PresetDrawer), matching: finder);

/// The drawer's one scroll list.
Finder get _drawerList => _inDrawer(find.byType(SingleChildScrollView));

/// The drawer's header: it wears the title bar's plate.
Finder get _drawerHeader => _inDrawer(
  find.byWidgetPredicate(
    (w) => w is DecoratedBox && identical(w.decoration, topBarDecoration),
  ),
);

/// The burger's whole hit target.
Finder get _burger => find
    .ancestor(
      of: find.byIcon(Icons.menu),
      matching: find.byType(SonicIconButton),
    )
    .first;

/// The title bar's save button: it sits under the drawer's scrim.
Finder get _save =>
    find.descendant(of: find.byType(TopBar), matching: find.byIcon(Icons.save));

/// The rail footer's plate (its top hairline and padding).
Finder get _footer => find
    .ancestor(of: find.text('by Skyggedans'), matching: find.byType(Container))
    .first;

/// The drawer row of the preset in [slot].
Finder _row(String slot) => find
    .ancestor(of: _inDrawer(find.text(slot)), matching: find.byType(PresetChip))
    .first;

/// The drawer list's scroll position.
ScrollPosition _drawerScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _drawerList, matching: find.byType(Scrollable)).first,
    )
    .position;

/// The work area's scroll position.
ScrollPosition _workScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .ancestor(
            of: find.byType(ChainView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// The app-level sideways scroll position.
ScrollPosition _appScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == .right,
          )
          .first,
    )
    .position;

/// The scrim's fade: 0 = clear, 1 = fully dimming. Looked up inside the drawer
/// (not by colour alone): a dialog's barrier shares Palette.scrim.
double _scrimOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: _inDrawer(
              find.byWidgetPredicate(
                (w) => w is ColoredBox && w.color == Palette.scrim,
              ),
            ),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

/// Whether the drawer's search field can take focus: only while the drawer is
/// open, because the panel's ExcludeFocus keeps a closed one out of focus.
bool _canFocusSearch(WidgetTester tester) => tester
    .widget<EditableText>(_inDrawer(find.byType(EditableText)))
    .focusNode
    .canRequestFocus;

/// Whether the sliding panel takes part in semantics: only while the drawer is
/// open. Closed, it is off-screen and clipped, so its nodes leave the tree
/// anyway; only the ExcludeSemantics right above the slide shows that it is
/// excluded. (find.bySemanticsLabel cannot say: it reads each render object's
/// last node, which an excluded one keeps after a close.)
bool _isPanelInSemantics(WidgetTester tester) => !tester
    .widget<ExcludeSemantics>(
      find
          .ancestor(
            of: _inDrawer(find.byType(AnimatedSlide)),
            matching: find.byType(ExcludeSemantics),
          )
          .first,
    )
    .excluding;

/// Expects the [slot] row about a third of the way down the drawer list: the
/// position ScrollPosition.ensureVisible(alignment: 1 / 3) gives it.
void _expectRevealed(WidgetTester tester, String slot) {
  final row = tester.getRect(_row(slot));
  final list = tester.getRect(_drawerList);

  expect(
    row.top - list.top,
    moreOrLessEquals((list.height - row.height) / 3, epsilon: 1),
  );
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(_burger);
  await tester.pumpAndSettle();
}

void main() {
  // Compact page tests keep the editor empty (selectedEffects: {}): the drawer
  // is under test, not the work area's density.
  group('compact preset drawer', () {
    testWidgets('closed by default: one burger in the slot, panel off-screen', (
      tester,
    ) async {
      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      final semantics = tester.ensureSemantics();

      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.bySemanticsLabel('Presets'), findsOneWidget);
      expect(tester.getCenter(_burger), const Offset(24, 24));
      // The title bar's icon padding: a 38x46 target in the 48-px bar.
      expect(tester.getSize(_burger), const Size(38, 46));
      expect(container.read(presetDrawerOpenProvider), isFalse);
      expect(tester.getRect(_drawerHeader).right, lessThanOrEqualTo(0));
      semantics.dispose();
    });

    testWidgets('the burger slides it in over the bar; the burger stays put', (
      tester,
    ) async {
      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      final burger = tester.getRect(_burger);
      final chain = tester.getRect(find.byType(ChainView));

      await tester.tap(_burger);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(container.read(presetDrawerOpenProvider), isTrue);
      expect(tester.getRect(_burger), burger);
      expect(
        tester.getRect(_drawerHeader).left,
        inExclusiveRange(-railWidth, 0),
      );

      await tester.pumpAndSettle();

      expect(tester.getRect(_burger), burger);
      // The header covers the bar's left part, title-bar tall.
      expect(
        tester.getRect(_drawerHeader),
        const Rect.fromLTWH(0, 0, railWidth, 48),
      );
      expect(
        tester.getRect(_inDrawer(find.byType(SonicLogo))).left,
        greaterThanOrEqualTo(drawerButtonSlotWidth),
      );
      expect(tester.getRect(_drawerList).top, 48);
      // An overlay: the work area never reflows under it.
      expect(tester.getRect(find.byType(ChainView)), chain);
    });

    testWidgets('a scrim tap closes it; the covered actions do not fire', (
      tester,
    ) async {
      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      await _openDrawer(tester);
      // tune sits right of the panel, under the scrim.
      await tester.tap(find.byIcon(Icons.tune), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(container.read(presetDrawerOpenProvider), isFalse);
      expect(find.byType(GlobalSettingsDialog), findsNothing);
      expect(tester.getRect(_drawerHeader).right, lessThanOrEqualTo(0));
    });

    testWidgets('the burger closes it', (tester) async {
      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      await _openDrawer(tester);
      await tester.tap(_burger);
      await tester.pumpAndSettle();

      expect(container.read(presetDrawerOpenProvider), isFalse);
      expect(tester.getRect(_drawerHeader).right, lessThanOrEqualTo(0));
    });

    testWidgets('one scrolling list: Master Vol, tabs, search, rows, footer', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );
      await _openDrawer(tester);

      expect(_drawerList, findsOneWidget);

      for (final finder in [
        find.text('MASTER VOL'),
        find.text('FACTORY'),
        find.byType(EditableText),
        find.text('P02'),
        find.text('by Skyggedans'),
      ]) {
        expect(
          find.descendant(of: _drawerList, matching: finder),
          findsOneWidget,
        );
      }
    });

    testWidgets('disconnected: it opens on the footer alone, pinned low', (
      tester,
    ) async {
      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        isConnected: false,
      );

      await _openDrawer(tester);

      expect(container.read(presetDrawerOpenProvider), isTrue);
      expect(_inDrawer(find.text('MASTER VOL')), findsNothing);
      expect(tester.getRect(_footer).bottom, 393);
    });

    // A phone's BLE link drops while the user browses the drawer.
    testWidgets(
      'a pedal drop leaves it open on the footer; reconnect restores',
      (tester) async {
        final container = await pumpPage(
          tester,
          size: const Size(852, 393),
          selectedEffects: const {},
        );

        await _openDrawer(tester);
        await tester.enterText(_inDrawer(find.byType(EditableText)), 'P06');
        await tester.pump();

        container.read(connectionStateProvider.notifier).state = false;
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(container.read(presetDrawerOpenProvider), isTrue);
        expect(_inDrawer(find.text('MASTER VOL')), findsNothing);
        expect(tester.getRect(_footer).bottom, 393);

        container.read(connectionStateProvider.notifier).state = true;
        await tester.pump();

        expect(
          tester
              .widget<EditableText>(_inDrawer(find.byType(EditableText)))
              .controller
              .text,
          'P06',
        );
        expect(_inDrawer(find.byType(PresetChip)), findsOneWidget);

        await tester.tap(_burger);
        await tester.pumpAndSettle();

        expect(container.read(presetDrawerOpenProvider), isFalse);
      },
    );

    for (final size in const [Size(568, 320), Size(640, 300)]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('$label: it opens without error; the footer is reachable', (
        tester,
      ) async {
        await pumpPage(tester, size: size, selectedEffects: const {});
        await _openDrawer(tester);

        expect(tester.takeException(), isNull);
        expect(tester.getSize(_drawerHeader), const Size(railWidth, 48));

        await tester.ensureVisible(find.text('by Skyggedans'));
        await tester.pump();

        expectWithin(
          tester.getRect(_footer),
          tester.getRect(_drawerList),
          'footer',
        );
      });
    }

    testWidgets('regular layout: no drawer and no burger', (tester) async {
      await pumpPage(tester, size: const Size(1280, 800));

      expect(find.byType(PresetDrawer), findsNothing);
      expect(find.byIcon(Icons.menu), findsNothing);
    });
  });

  group('closing the drawer', () {
    testWidgets('Back closes it; a closed drawer lets Back leave the app', (
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

      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      await _openDrawer(tester);
      await simulateSystemBack(tester);
      await tester.pumpAndSettle();

      expect(container.read(presetDrawerOpenProvider), isFalse);
      expect(calls, isNot(contains('SystemNavigator.pop')));

      await simulateSystemBack(tester);

      expect(calls, contains('SystemNavigator.pop'));
    });

    testWidgets('a pick closes it and loads the preset', (tester) async {
      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      await _openDrawer(tester);
      await tester.ensureVisible(_inDrawer(find.text('P02')));
      await tester.pump();
      await tester.tap(_inDrawer(find.text('P02')));
      await tester.pump();

      expect(container.read(presetDrawerOpenProvider), isFalse);
      expect(container.read(presetLoadingProvider), isTrue);

      await pumpPastAckTimeout(tester);

      expect(container.read(presetLoadStatusProvider), 'P02: no ACK (timeout)');
    });

    testWidgets('unsaved edits + Cancel keep it open and load nothing', (
      tester,
    ) async {
      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
        overrides: [presetModifiedProvider.overrideWith((_) => true)],
      );

      await _openDrawer(tester);
      await tester.ensureVisible(_inDrawer(find.text('P02')));
      await tester.pump();
      await tester.tap(_inDrawer(find.text('P02')));
      await tester.pumpAndSettle();

      expect(find.text('Discard unsaved changes?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(presetDrawerOpenProvider), isTrue);
      expect(container.read(presetLoadingProvider), isFalse);
    });

    testWidgets('Back with the unsaved-changes dialog up dismisses only it', (
      tester,
    ) async {
      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
        overrides: [presetModifiedProvider.overrideWith((_) => true)],
      );

      await _openDrawer(tester);
      await tester.ensureVisible(_inDrawer(find.text('P02')));
      await tester.pump();
      await tester.tap(_inDrawer(find.text('P02')));
      await tester.pumpAndSettle();
      await simulateSystemBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('Discard unsaved changes?'), findsNothing);
      expect(container.read(presetDrawerOpenProvider), isTrue);
      expect(container.read(presetLoadingProvider), isFalse);
    });

    testWidgets('closing it takes the focus off its search field', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );
      await _openDrawer(tester);

      final search = _inDrawer(find.byType(EditableText));

      await tester.tap(search);
      await tester.pump();

      expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);

      // Under flutter test a touch outside a field never unfocuses it, so
      // only the drawer itself can drop the focus here.
      await tester.tap(_burger);
      await tester.pump();

      expect(tester.widget<EditableText>(search).focusNode.hasFocus, isFalse);
    });
  });

  group('opening reveals the loaded preset', () {
    testWidgets('its row lands about a third down the list', (tester) async {
      await pumpPage(
        tester,
        size: const Size(852, 393),
        current: const PresetRef(.user, 40),
        selectedEffects: const {},
      );
      await _openDrawer(tester);

      _expectRevealed(tester, 'P40');
    });

    testWidgets('a row already in full view stays where it is', (tester) async {
      // Compact (narrower than 960) and tall enough to show P01 at once.
      await pumpPage(
        tester,
        size: const Size(900, 1000),
        selectedEffects: const {},
      );
      await _openDrawer(tester);

      expect(_drawerScroll(tester).pixels, 0);
    });

    testWidgets('a preset of the other bank leaves the list alone', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(852, 393),
        current: const PresetRef(.factory, 40),
        selectedEffects: const {},
      );
      await _openDrawer(tester);

      expect(_drawerScroll(tester).pixels, 0);
    });

    testWidgets('a preset the search filters out leaves the list alone', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(852, 393),
        current: const PresetRef(.user, 40),
        selectedEffects: const {},
        overrides: [presetSearchProvider.overrideWith((_) => 'P0')],
      );
      await _openDrawer(tester);

      expect(_drawerScroll(tester).pixels, 0);
    });

    // The user scrolls up to the Master Vol knob, closes the drawer, and
    // reopens it later: it opens on the loaded preset again.
    testWidgets('every opening re-reveals it after the list was scrolled', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(852, 393),
        current: const PresetRef(.user, 40),
        selectedEffects: const {},
      );
      await _openDrawer(tester);
      _drawerScroll(tester).jumpTo(0);
      await tester.pump();
      await tester.tap(_burger);
      await tester.pumpAndSettle();
      await _openDrawer(tester);

      _expectRevealed(tester, 'P40');
    });

    testWidgets('it never moves the work area or the sideways scroll', (
      tester,
    ) async {
      // 568 wide: the 640-wide app is scrolled 30 px sideways.
      await pumpPage(
        tester,
        size: const Size(568, 320),
        current: const PresetRef(.user, 40),
        selectedEffects: const {},
      );
      _appScroll(tester).jumpTo(30);
      await tester.pump();

      final work = _workScroll(tester).pixels;

      await tester.tapAt(tester.getCenter(_burger).translate(10, 0));
      await tester.pumpAndSettle();

      _expectRevealed(tester, 'P40');
      expect(_appScroll(tester).pixels, 30);
      expect(_workScroll(tester).pixels, work);
    });
  });

  group('layout flips', () {
    testWidgets('leaving compact closes it for good', (tester) async {
      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      await _openDrawer(tester);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();

      expect(container.read(presetDrawerOpenProvider), isFalse);

      tester.view.physicalSize = const Size(852, 393);
      await tester.pump();

      expect(tester.getRect(_drawerHeader).right, lessThanOrEqualTo(0));
    });

    testWidgets('a phone rotation keeps it open, full height', (tester) async {
      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      await _openDrawer(tester);
      tester.view.physicalSize = const Size(393, 852);
      await tester.pump();

      expect(container.read(presetDrawerOpenProvider), isTrue);
      expect(
        tester.getRect(_drawerList),
        const Rect.fromLTRB(0, 48, railWidth, 852),
      );
    });

    testWidgets('a load picked in the drawer survives a flip to regular', (
      tester,
    ) async {
      final container = await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      await _openDrawer(tester);
      await tester.ensureVisible(_inDrawer(find.text('P02')));
      await tester.pump();
      await tester.tap(_inDrawer(find.text('P02')));
      await tester.pump();

      expect(container.read(presetLoadingProvider), isTrue);

      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      await pumpPastAckTimeout(tester);

      expect(tester.takeException(), isNull);
      expect(container.read(presetLoadingProvider), isFalse);
      expect(container.read(presetLoadStatusProvider), 'P02: no ACK (timeout)');
    });

    // A tablet in portrait (compact) is turned to landscape (regular) while
    // the drawer search is being typed into, the soft keyboard up.
    testWidgets('a flip with the keyboard up keeps the filter, not the inset', (
      tester,
    ) async {
      final container = await pumpPage(
        tester,
        size: const Size(800, 1280),
        selectedEffects: const {},
      );

      await _openDrawer(tester);
      await tester.enterText(_inDrawer(find.byType(EditableText)), 'P06');
      await setKeyboard(tester, 300);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(container.read(presetDrawerOpenProvider), isFalse);
      // The regular layout ignores the stale inset: full height.
      expect(
        tester.getRect(find.byType(TopBar)),
        const Rect.fromLTWH(0, 0, 1280, 60),
      );
      expect(tester.getRect(find.byType(PresetRail)).bottom, 800);
      // The rail's search box shows the filter its list uses.
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byType(PresetRail),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'P06',
      );
      expect(
        find.descendant(
          of: find.byType(PresetRail),
          matching: find.byType(PresetChip),
        ),
        findsOneWidget,
      );
    });
  });

  // The closed drawer stays mounted over the whole app. Until it opens, its
  // scrim and panel must be inert: no swallowed tap, no dim, no semantics.
  group('closed-state invariants', () {
    testWidgets('closed: the scrim is clear and the app below takes taps', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      expect(_scrimOpacity(tester), 0);

      // save sits under the (inert) scrim and opens its dialog at once.
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.byType(SavePresetDialog), findsOneWidget);
    });

    testWidgets('open: the scrim dims the app', (tester) async {
      await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );
      await _openDrawer(tester);

      expect(_scrimOpacity(tester), 1);
    });

    testWidgets('closed: the panel is out of semantics; open: it is in', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      final semantics = tester.ensureSemantics();

      expect(find.bySemanticsLabel('by Skyggedans'), findsNothing);

      await _openDrawer(tester);

      expect(find.bySemanticsLabel('by Skyggedans'), findsOneWidget);
      semantics.dispose();
    });

    // An opening must latch nothing: once the closing slide has finished, the
    // drawer is as inert as one that was never opened.
    testWidgets('closed again after an open and a close: still inert', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      await _openDrawer(tester);

      expect(_scrimOpacity(tester), 1);
      expect(_isPanelInSemantics(tester), isTrue);
      expect(_canFocusSearch(tester), isTrue);

      await tester.tap(_burger);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(_scrimOpacity(tester), 0);
      expect(_isPanelInSemantics(tester), isFalse);
      expect(_canFocusSearch(tester), isFalse);

      // save sits under the (inert) scrim and opens its dialog at once.
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.byType(SavePresetDialog), findsOneWidget);
    });
  });
}
