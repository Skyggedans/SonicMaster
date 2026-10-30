import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/ui/chain_view.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/preset_drawer.dart';
import 'package:sonicmaster/ui/preset_fields_panel.dart';
import 'package:sonicmaster/ui/preset_rail.dart';
import 'package:sonicmaster/ui/top_bar.dart';

import '../support/page_harness.dart';
import '../support/view_helpers.dart';

/// The work area's vertical scroll view.
Finder get _workArea => find
    .ancestor(of: find.byType(ChainView), matching: find.byType(Scrollable))
    .first;

/// The compact drawer's preset search field.
Finder get _drawerSearch => find.descendant(
  of: find.byType(PresetDrawer),
  matching: find.byType(EditableText),
);

/// The part of an 852x393 screen between the drawer's header and a 180-px
/// keyboard: the drawer list's visible strip.
const _drawerStrip = Rect.fromLTRB(0, 48, 852, 393 - 180);

/// Opens the compact drawer, focuses its search field and raises a 180-px
/// keyboard.
Future<void> _focusDrawerSearch(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(_drawerSearch);
  await tester.pump();
  await setKeyboard(tester, 180);
}

/// Lets a focused field's caret reveal finish: when the field was focused one
/// frame earlier, EditableText scrolls it into view with a 100-ms animation,
/// whose ticker starts on the next frame.
Future<void> _finishCaretReveal(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

/// Lets the caret reveal of a keystroke finish: enterText pumps no frame
/// after the edit, so the reveal starts at the end of the next one.
Future<void> _finishTypingReveal(WidgetTester tester) async {
  await tester.pump();
  await _finishCaretReveal(tester);
}

void main() {
  // The page is the only owner of the soft-keyboard inset: in compact it ends
  // the whole app (bar, work area, drawer) above the keyboard, so a focused
  // field's own show-on-screen can scroll it into view.
  testWidgets('compact: the drawer search field stays above the keyboard', (
    tester,
  ) async {
    await pumpPage(tester, size: const Size(852, 393));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final search = find.descendant(
      of: find.byType(PresetDrawer),
      matching: find.byType(EditableText),
    );

    await tester.tap(search);
    await tester.pump();
    await setKeyboard(tester, 180);
    await _finishCaretReveal(tester);

    // The drawer list ends at the keyboard: the page lifted the whole app.
    expect(
      tester
          .getRect(
            find.descendant(
              of: find.byType(PresetDrawer),
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .bottom,
      393 - 180,
    );
    expectWithin(
      tester.getRect(search),
      const Rect.fromLTRB(0, 0, 852, 393 - 180),
      'search field',
    );
  });

  // Revealing the focused search reveals the list below it too: the matches
  // show above the keyboard while the user types, not only after Done.
  testWidgets('compact: drawer search matches show while typing', (
    tester,
  ) async {
    await pumpPage(
      tester,
      size: const Size(852, 393),
      names: {
        for (final i in [1, 2, 3, 4, 5]) PresetRef(.user, i): 'Crunch $i',
      },
    );
    await _focusDrawerSearch(tester);
    await tester.enterText(_drawerSearch, 'cr');
    await _finishTypingReveal(tester);

    expectWithin(
      tester.getRect(
        find
            .descendant(
              of: find.byType(PresetDrawer),
              matching: find.byType(PresetChip),
            )
            .first,
      ),
      _drawerStrip,
      'first match',
    );
  });

  // The room revealed below the field is capped by the list's height: a
  // reveal taller than the list would leave a field scrolled out of view
  // hidden while the user types.
  testWidgets('compact: a keystroke brings a scrolled-away search back', (
    tester,
  ) async {
    await pumpPage(tester, size: const Size(852, 393));
    await _focusDrawerSearch(tester);
    await _finishCaretReveal(tester);

    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(PresetDrawer),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(600);
    await tester.pump();

    expect(tester.getRect(_drawerSearch).bottom, lessThan(48));

    // 'p' matches every slot label (P01-P50): the list stays long, so only
    // the reveal can bring the field back.
    await tester.enterText(_drawerSearch, 'p');
    await _finishTypingReveal(tester);

    expectWithin(tester.getRect(_drawerSearch), _drawerStrip, 'search field');
  });

  testWidgets('compact: a knob value being typed stays above the keyboard', (
    tester,
  ) async {
    await pumpPage(tester, size: const Size(852, 393));

    final patchVol = find
        .descendant(
          of: find.byType(PresetFieldsPanel),
          matching: find.byType(KnobControl),
        )
        .first;

    final readout = find.descendant(of: patchVol, matching: find.text('44'));

    // As low on the screen as the work area scrolls it: where the keyboard
    // is about to come up.
    await Scrollable.ensureVisible(tester.element(readout), alignment: 1);
    await tester.pump();
    // Double-tap the value: the knob's inline editor opens, focused.
    await tester.tap(readout);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(readout);
    await tester.pump();
    await setKeyboard(tester, 180);
    await _finishCaretReveal(tester);

    expect(tester.getRect(_workArea).bottom, 393 - 180);
    expectWithin(
      tester.getRect(
        find.descendant(of: patchVol, matching: find.byType(EditableText)),
      ),
      const Rect.fromLTRB(0, 0, 852, 393 - 180),
      'knob value field',
    );
  });

  testWidgets('compact 740x280 with a 220-px keyboard lays out cleanly', (
    tester,
  ) async {
    await pumpPage(tester, size: const Size(740, 280));
    await setKeyboard(tester, 220);

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(TopBar)),
      const Rect.fromLTWH(0, 0, 740, 48),
    );
    expect(tester.getRect(_workArea).bottom, 280 - 220);
  });

  testWidgets('regular: the keyboard never resizes the page', (tester) async {
    await pumpPage(tester, size: const Size(1280, 800));

    final bar = tester.getRect(find.byType(TopBar));
    final workArea = tester.getRect(_workArea);

    await setKeyboard(tester, 300);

    expect(tester.getRect(find.byType(TopBar)), bar);
    expect(tester.getRect(_workArea), workArea);
    expect(workArea.bottom, 800);
  });
}
