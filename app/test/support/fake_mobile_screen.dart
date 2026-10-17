import 'dart:async';

import 'package:sonicmaster/state/mobile_screen.dart';

/// A scriptable [MobileScreen] for widget tests: the real one is web-only, and
/// `flutter test` compiles the native stub. The defaults are an Android phone
/// in Chrome: a phone-sized touch browser that can go fullscreen and hold
/// landscape, not fullscreen yet.
///
/// Like a browser, entering and leaving only ask: the state changes when a
/// test calls [simulateFullscreenChange] (the browser granting the request,
/// Back, an app switch, a permission prompt).
class FakeMobileScreen implements MobileScreen {
  FakeMobileScreen({
    this.isTouchBrowser = true,
    this.isPhoneScreen = true,
    this.isFullscreenAvailable = true,
    this.isLandscapeLockSupported = true,
    this._isFullscreen = false,
  });

  @override
  final bool isTouchBrowser;

  @override
  final bool isPhoneScreen;

  @override
  final bool isFullscreenAvailable;

  @override
  final bool isLandscapeLockSupported;

  bool _isFullscreen;

  /// How often [enterLandscapeFullscreen] was called.
  int enterCount = 0;

  /// How often [exitFullscreen] was called.
  int exitCount = 0;

  final _changes = StreamController<bool>.broadcast();

  @override
  bool get isFullscreen => _isFullscreen;

  @override
  Stream<bool> get fullscreenChanges => _changes.stream;

  /// A fullscreen change from outside the app, reported the way the browser
  /// reports it ('fullscreenchange').
  void simulateFullscreenChange({required bool isFullscreen}) {
    _isFullscreen = isFullscreen;
    _changes.add(isFullscreen);
  }

  @override
  Future<void> enterLandscapeFullscreen() async {
    enterCount++;
  }

  @override
  Future<void> exitFullscreen() async {
    exitCount++;
  }

  @override
  void dispose() => unawaited(_changes.close());
}
