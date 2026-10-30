import 'dart:async';

import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/mobile_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';
import 'sonic_metrics.dart';

/// Blocks a phone held in portrait with a "Rotate your device to landscape"
/// prompt: on phones the compact layout is landscape-only.
///
/// It sits in WidgetsApp.builder, above the Navigator, so it covers dialogs
/// too, and the app stays mounted underneath with all its state.
///
/// * Off phone browsers (desktop, tablets, native) it returns [child] as is.
///   That is fixed for the session ([MobileScreen.isTouchBrowser] and
///   [MobileScreen.isPhoneScreen] never change), so the tree never switches
///   shape.
/// * On phones the shape is always `Stack[ExcludeFocus(child), prompt?]`:
///   [child] keeps index 0 and its ExcludeFocus in both orientations, so a
///   rotation never remounts the FocusScope + Navigator WidgetsApp hands to the
///   builder.
///
/// While the prompt is up the app has no keyboard focus, so an open text field
/// loses it and the soft keyboard closes; a knob value editor in the compact
/// layout commits its value on that. Two side effects are accepted:
/// WidgetsApp's startup autofocus is refused when the app opens in portrait,
/// and a browser Back still pops a dialog (or closes the drawer) hidden under
/// the prompt.
class RotateDeviceOverlay extends ConsumerWidget {
  const RotateDeviceOverlay({super.key, required this.child});

  /// The app: WidgetsApp's FocusScope + Navigator.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = ref.watch(mobileScreenProvider);

    if (!screen.isTouchBrowser || !screen.isPhoneScreen) return child;

    final isPortrait = MediaQuery.orientationOf(context) == .portrait;

    return Stack(
      fit: .expand,
      children: [
        ExcludeFocus(excluding: isPortrait, child: child),
        if (isPortrait)
          _RotatePrompt(
            isFullscreenOffered:
                screen.isFullscreenAvailable && screen.isLandscapeLockSupported,
            onFullscreen: () => unawaited(screen.enterLandscapeFullscreen()),
          ),
      ],
    );
  }
}

/// The portrait prompt: an opaque page that takes every pointer and hides the
/// app from screen readers, with a plate in the dialogs' look. A plain
/// [SonicSurface], not a [SonicDialog]: this sits above the Navigator, and
/// the dialog shell's own scroll and keyboard lift are for routes.
class _RotatePrompt extends StatelessWidget {
  const _RotatePrompt({
    required this.isFullscreenOffered,
    required this.onFullscreen,
  });

  /// Fullscreen plus the landscape lock turn the screen even with the system
  /// auto-rotate off. Offered only where both work (Android).
  final bool isFullscreenOffered;

  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final metrics = SonicMetrics.of(context);

    return BlockSemantics(
      child: ColoredBox(
        color: Palette.background,
        child: Center(
          child: SingleChildScrollView(
            padding: metrics.dialogMargin,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SonicSurface(
                radius: 16,
                padding: metrics.dialogPadding,
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    const Icon(
                      Icons.screen_rotation,
                      size: 48,
                      color: Palette.accent,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Rotate your device to landscape',
                      textAlign: .center,
                      style: AppText.dialogTitle,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The SonicMaster editor is laid out for a landscape '
                      'screen.',
                      textAlign: .center,
                      style: AppText.dialogBody,
                    ),
                    if (isFullscreenOffered) ...[
                      const SizedBox(height: 20),
                      SonicButton(
                        label: 'Fullscreen',
                        isAccent: true,
                        onPressed: onFullscreen,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fullscreen also turns the screen when auto-rotate '
                        'is off.',
                        textAlign: .center,
                        style: AppText.dialogBody.copyWith(
                          color: Palette.textDim,
                        ),
                      ),
                    ] else ...[
                      // The prompt cannot turn the screen here (iPhone, a
                      // frame without fullscreen), so a rotation lock would
                      // leave the app blocked. Fixed for the session, like
                      // the button: the tree never switches shape.
                      const SizedBox(height: 8),
                      Text(
                        'If the screen does not turn, switch off the rotation '
                        'lock.',
                        textAlign: .center,
                        style: AppText.dialogBody.copyWith(
                          color: Palette.textDim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
