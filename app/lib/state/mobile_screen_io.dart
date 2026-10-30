import 'mobile_screen.dart';

/// Native builds, and `flutter test` (which compiles this side), have no
/// browser around them: never a touch browser, never fullscreen. Native
/// Android/iOS runners (a later phase) will hold landscape natively instead.
MobileScreen createMobileScreen() => const _NativeScreen();

class _NativeScreen implements MobileScreen {
  const _NativeScreen();

  @override
  bool get isTouchBrowser => false;

  @override
  bool get isPhoneScreen => false;

  @override
  bool get isFullscreenAvailable => false;

  @override
  bool get isLandscapeLockSupported => false;

  @override
  bool get isFullscreen => false;

  @override
  Stream<bool> get fullscreenChanges => const Stream.empty();

  @override
  Future<void> enterLandscapeFullscreen() async {}

  @override
  Future<void> exitFullscreen() async {}

  @override
  void dispose() {}
}
