import 'dart:async';

import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/mobile_screen.dart';
import 'sonic_controls.dart';
import 'sonic_metrics.dart';

/// The compact title bar's fullscreen toggle. On phones, entering also holds
/// the screen in landscape, either way up. Collapses to nothing where the
/// browser cannot go fullscreen: desktop browsers, iPhone, an app installed
/// with `display: fullscreen`, and native builds.
///
/// Only the compact TopBar places it, so the regular title bar stays exactly
/// as it is. Sized by [SonicMetrics.topBarIconPadding] like the bar's other
/// icons (38x46 in compact).
class FullscreenButton extends ConsumerWidget {
  const FullscreenButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = ref.watch(mobileScreenProvider);

    if (!screen.isTouchBrowser || !screen.isFullscreenAvailable) {
      return const SizedBox.shrink();
    }

    final isFullscreen = ref.watch(isFullscreenProvider);

    return Semantics(
      button: true,
      label: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
      child: SonicIconButton(
        icon: isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
        padding: SonicMetrics.of(context).topBarIconPadding,
        // Straight from the tap, reading the live state: requestFullscreen
        // needs the tap's user activation, and the icon may lag a change the
        // browser made a moment ago.
        onPressed: () => unawaited(
          screen.isFullscreen
              ? screen.exitFullscreen()
              : screen.enterLandscapeFullscreen(),
        ),
      ),
    );
  }
}
