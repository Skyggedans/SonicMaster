@TestOn('chrome')
library;

import 'dart:js_interop_unsafe';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/mobile_screen.dart';
import 'package:sonicmaster/state/mobile_screen_web.dart';
import 'package:web/web.dart' as web;

/// Plumbing only: the suite runs in package:test's iframe, with no user
/// activation and no real rotation. Fullscreen, the landscape lock and
/// auto-fullscreen are proven on a real phone only.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  MobileScreen create() {
    final screen = createMobileScreen();

    addTearDown(screen.dispose);

    return screen;
  }

  test('a desktop browser driven by a mouse is not a touch browser', () {
    debugDefaultTargetPlatformOverride = .linux;

    final screen = create();

    expect(screen.isTouchBrowser, isFalse);
    expect(screen.isLandscapeLockSupported, isFalse);
  });

  test('a mobile OS is a touch browser', () {
    debugDefaultTargetPlatformOverride = .android;

    expect(create().isTouchBrowser, isTrue);
  });

  test('the phone check reads the short side of window.screen', () {
    final screen = web.window.screen;

    expect(
      create().isPhoneScreen,
      isPhoneScreenSize(
        Size(screen.width.toDouble(), screen.height.toDouble()),
      ),
    );
  });

  test('the landscape lock needs Android and screen.orientation.lock', () {
    debugDefaultTargetPlatformOverride = .android;

    final orientation = web.window.screen.orientation;

    expect(create().isLandscapeLockSupported, orientation.has('lock'));
  });

  test('reports the unprefixed fullscreenchange, not the webkit one', () async {
    final screen = create();
    final events = <bool>[];
    final subscription = screen.fullscreenChanges.listen(events.add);

    addTearDown(subscription.cancel);
    web.document.dispatchEvent(web.Event('webkitfullscreenchange'));
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);

    web.document.dispatchEvent(web.Event('fullscreenchange'));
    await Future<void>.delayed(Duration.zero);

    expect(events, [false]);
  });

  test('without a user gesture, entering fullscreen fails quietly', () async {
    final screen = create();

    await expectLater(screen.enterLandscapeFullscreen(), completes);
    expect(screen.isFullscreen, isFalse);
  });

  test('leaving fullscreen when not fullscreen is a no-op', () async {
    await expectLater(create().exitFullscreen(), completes);
  });

  test('dispose ends the fullscreen stream', () async {
    final screen = createMobileScreen();
    final done = expectLater(screen.fullscreenChanges, emitsDone);

    screen.dispose();
    web.document.dispatchEvent(web.Event('fullscreenchange'));

    await done;
  });
}
