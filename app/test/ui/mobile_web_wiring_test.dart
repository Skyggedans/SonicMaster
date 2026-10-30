import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/state/mobile_screen.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/fullscreen_button.dart';
import 'package:sonicmaster/ui/preset_browser_page.dart';
import 'package:sonicmaster/ui/rotate_device_overlay.dart';
import 'package:sonicmaster/ui/save_preset_dialog.dart';
import 'package:sonicmaster/ui/top_bar.dart';

import '../support/fake_mobile_screen.dart';
import '../support/page_harness.dart';
import '../support/silent_transport.dart';
import '../support/view_helpers.dart';

const prompt = 'Rotate your device to landscape';
const phoneLandscape = Size(852, 393);
const phonePortrait = Size(393, 852);

/// An Android phone in Chrome, or [screen]. The harness itself never
/// overrides mobileScreenProvider: without this the native stub answers.
List<Override> touchScreen([FakeMobileScreen? screen]) => [
  mobileScreenProvider.overrideWithValue(screen ?? FakeMobileScreen()),
];

/// Finders scoped to the title bar or the Save dialog: in compact the closed
/// drawer stays mounted, with its own search field and preset rows.
Finder inBar(Finder finder) =>
    find.descendant(of: find.byType(TopBar), matching: finder);

Finder inSaveDialog(Finder finder) =>
    find.descendant(of: find.byType(SavePresetDialog), matching: finder);

/// Turns the phone: a new view size, then one frame.
Future<void> turn(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump();
}

/// Opens the Save dialog from the title bar; its route fades in over 160 ms.
Future<void> openSaveDialog(WidgetTester tester) async {
  await tester.tap(inBar(find.byIcon(Icons.save)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('the rotate prompt wraps the Navigator in the real app', (
    tester,
  ) async {
    await pumpPage(tester, size: const Size(1280, 800), isConnected: false);

    expect(
      find.ancestor(
        of: find.byType(Navigator).first,
        matching: find.byType(RotateDeviceOverlay),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a phone in portrait: the prompt covers the whole page', (
    tester,
  ) async {
    await pumpPage(
      tester,
      size: phonePortrait,
      isConnected: false,
      overrides: touchScreen(),
    );

    expectNoOverflow(tester);
    expect(find.text(prompt).hitTestable(), findsOneWidget);
    expect(find.byType(PresetBrowserPage), findsOneWidget);
    expect(inBar(find.text('Connect')).hitTestable(), findsNothing);
  });

  testWidgets('a phone in landscape: the toggle sits between preset and tune', (
    tester,
  ) async {
    final screen = FakeMobileScreen();

    await pumpPage(
      tester,
      size: phoneLandscape,
      overrides: touchScreen(screen),
    );

    final toggle = inBar(find.byType(FullscreenButton));

    expect(find.text(prompt), findsNothing);
    expect(tester.getSize(toggle), const Size(38, 46));
    expect(
      tester.getRect(toggle).left,
      greaterThan(tester.getRect(inBar(find.text('Clean'))).right),
    );
    expect(
      tester.getCenter(toggle).dx,
      lessThan(tester.getCenter(inBar(find.byIcon(Icons.tune))).dx),
    );

    await tester.tap(toggle);

    expect(screen.enterCount, 1);
  });

  for (final size in const [Size(640, 360), Size(568, 320)]) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('$label: the longest name, the toggle and Disconnect fit', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: size,
        names: {const PresetRef(.user, 1): 'WWWWWWWWWW'},
        overrides: touchScreen(),
      );

      expectNoOverflow(tester);

      final bar = tester.getRect(find.byType(TopBar));
      final name = inBar(find.text('WWWWWWWWWW'));
      final toggle = tester.getRect(inBar(find.byType(FullscreenButton)));

      expect(bar.width, 640); // the compact minimum: narrower phones scroll
      expectWithin(toggle, bar, 'FullscreenButton');
      expectWithin(
        tester.getRect(inBar(find.text('Disconnect'))),
        bar,
        'Disconnect',
      );
      expect(tester.getRect(name).right, lessThanOrEqualTo(toggle.left));
      // Ten characters is the longest name the pedal stores; it still fits.
      expect(
        tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
        isFalse,
      );
    });
  }

  testWidgets('a tablet in portrait: compact bar with the toggle, no prompt', (
    tester,
  ) async {
    await pumpPage(
      tester,
      size: const Size(800, 1280),
      overrides: touchScreen(FakeMobileScreen(isPhoneScreen: false)),
    );

    expectNoOverflow(tester);
    expect(find.text(prompt), findsNothing);
    expect(inBar(find.byIcon(Icons.fullscreen)), findsOneWidget);
  });

  testWidgets('a tablet in landscape keeps the regular bar, no toggle', (
    tester,
  ) async {
    await pumpPage(
      tester,
      size: const Size(1280, 800),
      overrides: touchScreen(FakeMobileScreen(isPhoneScreen: false)),
    );

    expect(find.byType(FullscreenButton), findsNothing);
    expect(find.text(prompt), findsNothing);
  });

  testWidgets('native builds and desktop browsers get neither', (tester) async {
    await pumpPage(tester, size: phonePortrait, isConnected: false);

    expect(find.text(prompt), findsNothing);
    expect(find.byIcon(Icons.fullscreen), findsNothing);
  });

  testWidgets('turning to portrait mid-typing keeps the Save dialog and text', (
    tester,
  ) async {
    await pumpPage(tester, size: phoneLandscape, overrides: touchScreen());
    await openSaveDialog(tester);

    final nameField = inSaveDialog(find.byType(EditableText));

    EditableTextState field() => tester.state<EditableTextState>(nameField);

    await tester.enterText(nameField, 'Lead');
    await setKeyboard(tester, 180);

    final dialog = tester.element(find.byType(SavePresetDialog));

    expect(field().widget.focusNode.hasFocus, isTrue);

    await turn(tester, phonePortrait);
    await setKeyboard(tester, 0); // the browser drops it with the focus

    expect(find.text(prompt).hitTestable(), findsOneWidget);
    expect(nameField.hitTestable(), findsNothing);
    expect(field().widget.focusNode.hasFocus, isFalse);

    await turn(tester, phoneLandscape);

    expect(find.text(prompt), findsNothing);
    expect(tester.element(find.byType(SavePresetDialog)), same(dialog));
    expect(field().widget.controller.text, 'Lead');

    await tester.tap(nameField);
    await tester.pump();

    expect(field().widget.focusNode.hasFocus, isTrue);
  });

  testWidgets('a save in flight when the phone turns still ends cleanly', (
    tester,
  ) async {
    final container = await pumpPage(
      tester,
      size: phoneLandscape,
      overrides: touchScreen(),
    );

    await openSaveDialog(tester);
    await tester.tap(inSaveDialog(find.text('Save')));
    await tester.pump();

    expect(container.read(presetLoadingProvider), isTrue);

    await turn(tester, phonePortrait);

    expect(find.text(prompt), findsOneWidget);

    await pumpPastAckTimeout(tester);
    await tester.pump(const Duration(milliseconds: 200)); // the route fades

    expect(tester.takeException(), isNull);
    expect(container.read(presetLoadingProvider), isFalse);
    expect(container.read(presetLoadStatusProvider), 'save: no ACK (timeout)');
    expect(find.byType(SavePresetDialog), findsNothing);
  });
}
