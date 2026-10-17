import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:web/web.dart' as web;

import 'mobile_screen.dart';

/// How long [MobileScreen.enterLandscapeFullscreen] waits for
/// `screen.orientation.lock()`. Chrome settles the promise once the screen
/// has turned (well under a second); a browser that neither grants nor
/// refuses must not leave the call pending for good.
const _landscapeLockTimeout = Duration(seconds: 3);

/// The browser's screen, over the Fullscreen and Screen Orientation APIs. Read
/// once at startup: one instance per ProviderContainer (the app has one).
MobileScreen createMobileScreen() {
  final screen = web.window.screen;
  final orientation = _screenOrientation;
  final isDisplayModeFullscreen = web.window
      .matchMedia('(display-mode: fullscreen)')
      .matches;

  return _BrowserScreen(
    isTouchBrowser: isTouchPlatform(
      hasCoarsePointer: web.window.matchMedia('(pointer: coarse)').matches,
      platform: defaultTargetPlatform,
    ),
    isPhoneScreen: isPhoneScreenSize(
      Size(screen.width.toDouble(), screen.height.toDouble()),
    ),
    // An app installed with `display: fullscreen` is fullscreen already; a
    // `standalone` install (from before the manifest change) still offers it.
    isFullscreenAvailable:
        !isDisplayModeFullscreen &&
        web.document.has('fullscreenEnabled') &&
        web.document.fullscreenEnabled,
    isLandscapeLockSupported:
        defaultTargetPlatform == .android &&
        orientation != null &&
        orientation.has('lock'),
    isDisplayModeFullscreen: isDisplayModeFullscreen,
  );
}

/// `screen.orientation`, or null where the browser has none (older Safari).
web.ScreenOrientation? get _screenOrientation {
  final screen = web.window.screen;

  return screen.has('orientation') ? screen.orientation : null;
}

class _BrowserScreen implements MobileScreen {
  _BrowserScreen({
    required this.isTouchBrowser,
    required this.isPhoneScreen,
    required this.isFullscreenAvailable,
    required this.isLandscapeLockSupported,
    required bool isDisplayModeFullscreen,
  }) {
    // Unprefixed on purpose: package:web's
    // EventStreamProviders.fullscreenChangeEvent is the legacy
    // 'webkitfullscreenchange', which Chrome on Android never fires.
    web.document.addEventListener('fullscreenchange', _onFullscreenChange);

    final orientation = _screenOrientation;
    final isLockablePhone =
        isTouchBrowser && isPhoneScreen && isLandscapeLockSupported;

    if (!isLockablePhone || orientation == null) return;

    // Installed with `display: fullscreen`: the lock works without the
    // Fullscreen API. Once, in case the browser ignores the manifest's
    // orientation.
    if (isDisplayModeFullscreen) unawaited(_lockLandscape());

    // Auto-fullscreen: armed once for the app's lifetime, and only where it
    // can work.
    if (isFullscreenAvailable) {
      _lastOrientationType = orientation.type;
      orientation.addEventListener('change', _onOrientationChange);
    }
  }

  @override
  final bool isTouchBrowser;

  @override
  final bool isPhoneScreen;

  @override
  final bool isFullscreenAvailable;

  @override
  final bool isLandscapeLockSupported;

  final _fullscreenChanges = StreamController<bool>.broadcast();

  /// The orientation before the latest change: tells a turn into landscape
  /// from a flip between the two landscapes.
  String _lastOrientationType = '';

  late final JSFunction _onFullscreenChange = _handleFullscreenChange.toJS;

  late final JSFunction _onOrientationChange = _handleOrientationChange.toJS;

  @override
  bool get isFullscreen =>
      web.document.has('fullscreenElement') &&
      web.document.fullscreenElement != null;

  @override
  Stream<bool> get fullscreenChanges => _fullscreenChanges.stream;

  @override
  Future<void> enterLandscapeFullscreen() async {
    if (isFullscreen) {
      await _lockLandscape();

      return;
    }

    // Before any await: the request has to run inside the caller's event.
    final request = _requestFullscreen();

    if (request != null) await _lockWhenFullscreen(request);
  }

  @override
  Future<void> exitFullscreen() async {
    if (!isFullscreen || !web.document.has('exitFullscreen')) return;

    try {
      await web.document.exitFullscreen().toDart;
    } catch (_) {
      // Already left (Back, an app switch) between the check and the call.
    }
  }

  @override
  void dispose() {
    web.document.removeEventListener('fullscreenchange', _onFullscreenChange);
    _screenOrientation?.removeEventListener('change', _onOrientationChange);
    unawaited(_fullscreenChanges.close());
  }

  /// Asks for fullscreen on the document root with the browser's bars (and
  /// Android's navigation bar) hidden. Synchronous on purpose: browsers grant
  /// it only inside a user gesture or an orientation 'change' dispatch. Null
  /// where it cannot be asked.
  JSPromise<JSAny?>? _requestFullscreen() {
    final root = web.document.documentElement;

    if (!isFullscreenAvailable ||
        root == null ||
        !root.has('requestFullscreen')) {
      return null;
    }

    try {
      return root.requestFullscreen(
        web.FullscreenOptions(navigationUI: 'hide'),
      );
    } catch (_) {
      return null; // a browser that throws instead of rejecting
    }
  }

  /// Waits for a fullscreen [request], then holds landscape. A refusal (no
  /// gesture, a browser policy) leaves the page as it was: the title-bar
  /// button and the prompt's Fullscreen button stay the way in.
  Future<void> _lockWhenFullscreen(JSPromise<JSAny?> request) async {
    try {
      await request.toDart;
    } catch (_) {
      return;
    }

    await _lockLandscape();
  }

  /// On a phone, holds landscape either way up (Android's sensor landscape,
  /// even with the system auto-rotate off); a tablet keeps its orientation,
  /// and with it its portrait compact layout. Chrome grants the lock only in
  /// fullscreen or in an app installed with `display: fullscreen`, and drops
  /// it when fullscreen ends, so nothing ever unlocks. Never throws: a
  /// refusal, or a promise still pending after [_landscapeLockTimeout],
  /// leaves the screen as it is.
  Future<void> _lockLandscape() async {
    final orientation = _screenOrientation;

    if (!isLandscapeLockSupported || !isPhoneScreen || orientation == null) {
      return;
    }

    try {
      await orientation.lock('landscape').toDart.timeout(_landscapeLockTimeout);
    } catch (_) {
      // Refused or never settled: the rotate prompt stays the fallback.
    }
  }

  void _handleFullscreenChange(web.Event _) {
    if (!_fullscreenChanges.isClosed) _fullscreenChanges.add(isFullscreen);
  }

  /// Auto-fullscreen: a turn from portrait into landscape enters fullscreen
  /// by itself.
  ///
  /// The request MUST stay synchronous inside this listener. Chromium waives
  /// requestFullscreen's user-activation rule only while a screen.orientation
  /// 'change' event is being dispatched (ScopedAllowFullscreen with
  /// kOrientationChange). There is no time window: an await, a microtask or a
  /// Flutter frame callback before the call makes the browser refuse it,
  /// silently.
  void _handleOrientationChange(web.Event _) {
    final orientation = _screenOrientation;

    if (orientation == null) return;

    final fromType = _lastOrientationType;
    final toType = orientation.type;

    _lastOrientationType = toType;

    if (!shouldAutoFullscreen(
      fromType: fromType,
      toType: toType,
      isFullscreen: isFullscreen,
    )) {
      return;
    }

    final request = _requestFullscreen();

    if (request != null) unawaited(_lockWhenFullscreen(request));
  }
}
