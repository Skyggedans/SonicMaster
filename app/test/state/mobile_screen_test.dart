import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/mobile_screen.dart';

import '../support/fake_mobile_screen.dart';

void main() {
  group('isTouchPlatform', () {
    test('a coarse primary pointer is touch, whatever the OS', () {
      expect(isTouchPlatform(hasCoarsePointer: true, platform: .linux), isTrue);
    });

    test('Android and iOS are touch even with a fine pointer', () {
      for (final platform in const <TargetPlatform>[.android, .iOS]) {
        expect(
          isTouchPlatform(hasCoarsePointer: false, platform: platform),
          isTrue,
        );
      }
    });

    test('a desktop OS driven by a mouse is not', () {
      for (final platform in const <TargetPlatform>[.linux, .macOS, .windows]) {
        expect(
          isTouchPlatform(hasCoarsePointer: false, platform: platform),
          isFalse,
        );
      }
    });
  });

  group('isPhoneScreenSize (short side under 600)', () {
    for (final (size, isPhone) in const [
      (Size(393, 852), true), // phone, portrait
      (Size(852, 393), true), // the same phone, landscape
      (Size(320, 568), true), // the smallest iPhone
      (Size(599, 1000), true), // one px under the line
      (Size(600, 960), false), // exactly on it
      (Size(768, 1024), false), // iPad
      (Size(800, 1280), false), // Android tablet, portrait
      (Size(1280, 800), false), // the same tablet, landscape
    ]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      test('$label is ${isPhone ? 'a phone' : 'not a phone'}', () {
        expect(isPhoneScreenSize(size), isPhone);
      });
    }
  });

  group('shouldAutoFullscreen', () {
    test('a turn from portrait into either landscape enters fullscreen', () {
      for (final toType in const ['landscape-primary', 'landscape-secondary']) {
        expect(
          shouldAutoFullscreen(
            fromType: 'portrait-primary',
            toType: toType,
            isFullscreen: false,
          ),
          isTrue,
        );
      }
    });

    test('not when already fullscreen', () {
      expect(
        shouldAutoFullscreen(
          fromType: 'portrait-primary',
          toType: 'landscape-primary',
          isFullscreen: true,
        ),
        isFalse,
      );
    });

    test('a flip between the landscapes does not pull a user back in', () {
      expect(
        shouldAutoFullscreen(
          fromType: 'landscape-primary',
          toType: 'landscape-secondary',
          isFullscreen: false,
        ),
        isFalse,
      );
    });

    test('turning to portrait never does', () {
      expect(
        shouldAutoFullscreen(
          fromType: 'landscape-primary',
          toType: 'portrait-primary',
          isFullscreen: false,
        ),
        isFalse,
      );
    });
  });

  test('native and test builds get the do-nothing stub', () async {
    final container = ProviderContainer();

    addTearDown(container.dispose);

    final screen = container.read(mobileScreenProvider);

    expect(screen.isTouchBrowser, isFalse);
    expect(screen.isPhoneScreen, isFalse);
    expect(screen.isFullscreenAvailable, isFalse);
    expect(screen.isLandscapeLockSupported, isFalse);
    expect(screen.isFullscreen, isFalse);
    expect(container.read(isFullscreenProvider), isFalse);
    await expectLater(screen.fullscreenChanges, emitsDone);
    await expectLater(screen.enterLandscapeFullscreen(), completes);
    await expectLater(screen.exitFullscreen(), completes);
  });

  test(
    'isFullscreenProvider starts from the live state and follows it',
    () async {
      final screen = FakeMobileScreen(isFullscreen: true);
      final container = ProviderContainer(
        overrides: [mobileScreenProvider.overrideWithValue(screen)],
      );

      addTearDown(container.dispose);

      expect(container.read(isFullscreenProvider), isTrue);

      screen.simulateFullscreenChange(isFullscreen: false); // e.g. Back
      await Future<void>.delayed(Duration.zero);

      expect(container.read(isFullscreenProvider), isFalse);

      screen.simulateFullscreenChange(isFullscreen: true);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(isFullscreenProvider), isTrue);
    },
  );

  test('the fake defaults to an Android phone in Chrome', () {
    final screen = FakeMobileScreen();

    expect(screen.isTouchBrowser, isTrue);
    expect(screen.isPhoneScreen, isTrue);
    expect(screen.isFullscreenAvailable, isTrue);
    expect(screen.isLandscapeLockSupported, isTrue);
    expect(screen.isFullscreen, isFalse);
  });
}
