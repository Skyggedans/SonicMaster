import 'package:flutter/services.dart';

/// Loads the bundled Oswald, so text lays out with the app's real metrics
/// (1.482-em lines) instead of the test font. Every test that pins a height,
/// a width or an overflow depends on it.
Future<void> loadOswald() async {
  final loader = FontLoader('Oswald')
    ..addFont(rootBundle.load('assets/fonts/Oswald.ttf'));

  await loader.load();
}
