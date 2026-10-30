import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails if the last frame reported an exception: a layout overflow or any
/// other error. Call it right after a fresh pump: the framework reports an
/// overflow once per render object, so a later pump can miss it
/// (module_editor_overflow_test's rule). Unlike that file's local helper, a
/// non-overflow error fails too instead of being swallowed by takeException.
void expectNoOverflow(WidgetTester tester) {
  final error = tester.takeException();

  if (error == null) return;

  fail(
    error.toString().contains('overflowed')
        ? 'Layout overflow: $error'
        : 'Unexpected exception (not an overflow): $error',
  );
}

/// Asserts that [inner] lies inside [outer], edges inclusive (sub-pixel float
/// noise ignored): e.g. a focused field and a dialog's primary action inside
/// the area above the soft keyboard.
void expectWithin(Rect inner, Rect outer, String reason) {
  const tolerance = 1e-6;

  final isInside =
      inner.left >= outer.left - tolerance &&
      inner.top >= outer.top - tolerance &&
      inner.right <= outer.right + tolerance &&
      inner.bottom <= outer.bottom + tolerance;

  expect(isInside, isTrue, reason: '$reason: $inner is not inside $outer');
}

/// Raises a simulated soft keyboard [bottom] logical px tall (0 hides it), then
/// pumps one frame. Like a mobile browser, it fills viewInsets.bottom only; the
/// view keeps its size, so the layout mode never changes with the keyboard.
Future<void> setKeyboard(WidgetTester tester, double bottom) async {
  tester.view.viewInsets = FakeViewPadding(
    bottom: bottom * tester.view.devicePixelRatio,
  );
  await tester.pump();
}

/// A system or browser Back exactly as the engine delivers it (on web:
/// popstate → `popRoute` on the navigation channel), then one frame. Routes
/// and PopScopes decide what it does; a Back that nobody handles calls
/// SystemNavigator.pop (the app is left).
Future<void> simulateSystemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(
      const MethodCall('popRoute'),
    ),
    (_) {},
  );
  await tester.pump();
}
