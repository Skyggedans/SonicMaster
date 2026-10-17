import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mobile_screen_io.dart'
    if (dart.library.js_interop) 'mobile_screen_web.dart';

/// What the compact web layout needs from the browser around it: is this a
/// phone or tablet browser, can it go fullscreen, and can it hold the screen
/// in landscape.
///
/// [createMobileScreen] picks the side at compile time (cf.
/// device/web_capabilities.dart): the browser's screen on web, and a stub that
/// says no to everything on native builds and under `flutter test`, where
/// widget tests inject a fake through [mobileScreenProvider].
abstract class MobileScreen {
  /// A phone or tablet browser (see [isTouchPlatform]). Fixed for the session.
  bool get isTouchBrowser;

  /// The device is phone-sized (see [isPhoneScreenSize]). Read once at
  /// startup. The rotate-to-landscape prompt, auto-fullscreen and the
  /// landscape hold apply to phones only: a tablet in portrait gets the
  /// compact layout instead.
  bool get isPhoneScreen;

  /// HTML fullscreen is available and worth offering. False on iPhone (no
  /// element fullscreen), in a frame without permission, and in an app
  /// installed with `display: fullscreen` (already fullscreen). Installs from
  /// before that manifest change (`standalone`) keep it.
  bool get isFullscreenAvailable;

  /// `screen.orientation.lock('landscape')` can hold landscape: Android only,
  /// by the user agent: false in Chrome's desktop-site mode. iPadOS can go
  /// fullscreen but always refuses the lock.
  bool get isLandscapeLockSupported;

  /// The page is in HTML fullscreen right now.
  bool get isFullscreen;

  /// [isFullscreen] after every change, whatever caused it: the title-bar
  /// button, a rotation, Back, an app switch, a file picker or a permission
  /// prompt.
  Stream<bool> get fullscreenChanges;

  /// Enters fullscreen with the browser's bars hidden and, on a phone, holds
  /// the screen in landscape, either way up, even with the system auto-rotate
  /// off. Call it straight from a tap: browsers only grant fullscreen to a
  /// user gesture. Never throws; a refusal leaves the page as it was.
  Future<void> enterLandscapeFullscreen();

  /// Leaves fullscreen; the browser drops the landscape hold with it. Never
  /// throws.
  Future<void> exitFullscreen();

  /// Stops listening to the browser.
  void dispose();
}

/// A phone or tablet browser: a coarse primary pointer (a finger), or a
/// mobile OS. The pointer check catches Chrome's desktop-site mode, whose
/// user agent drops "Android" (Flutter then reports Linux, so the OS check,
/// and with it the landscape lock and auto-fullscreen, miss it); the OS check
/// catches a phone driven by a mouse.
bool isTouchPlatform({
  required bool hasCoarsePointer,
  required TargetPlatform platform,
}) => hasCoarsePointer || platform == .android || platform == .iOS;

/// A phone-sized screen: its short side is under 600 logical px. That is the
/// compact layout's 600-px height line applied to the physical screen, so a
/// tablet (600 px or more on its short side) never counts as a phone. Screens
/// report the same short side in either orientation.
bool isPhoneScreenSize(Size screen) =>
    math.min(screen.width, screen.height) < 600;

/// Whether a screen-orientation change enters fullscreen by itself: only a
/// turn from portrait into landscape, and only when not fullscreen already. A
/// flip between the two landscapes does not count, so after the user leaves
/// fullscreen (Back) they are not pulled back in until they turn the device
/// to portrait and back.
bool shouldAutoFullscreen({
  required String fromType,
  required String toType,
  required bool isFullscreen,
}) =>
    !isFullscreen &&
    fromType.startsWith('portrait') &&
    toType.startsWith('landscape');

/// The app's [MobileScreen]: the browser's on web, a do-nothing stub on
/// native. One instance per ProviderContainer (the app has one, main.dart);
/// RotateDeviceOverlay reads it on the first frame, which arms the browser
/// side's auto-fullscreen.
final mobileScreenProvider = Provider<MobileScreen>((ref) {
  final screen = createMobileScreen();

  ref.onDispose(screen.dispose);

  return screen;
});

/// Whether the page is fullscreen, kept current: seeded from the live state
/// and recomputed on every change, so a Back press flips the title-bar icon.
///
/// A synchronous Provider rather than a StreamProvider, so readers get a plain
/// bool on the first frame. In widget tests, let a simulated change land with
/// `pump(Duration.zero)` or `pumpAndSettle()`: a bare `pump()` checks for a
/// scheduled frame before it flushes the microtask that rebuilds this.
final isFullscreenProvider = Provider<bool>((ref) {
  final screen = ref.watch(mobileScreenProvider);
  final subscription = screen.fullscreenChanges.listen(
    (_) => ref.invalidateSelf(),
  );

  ref.onDispose(subscription.cancel);

  return screen.isFullscreen;
});
