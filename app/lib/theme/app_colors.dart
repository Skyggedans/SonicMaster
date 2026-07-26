import 'package:flutter/painting.dart';

/// Central palette of the recurring, semantic colors used across the UI.
///
/// This names the colors that carry meaning and/or repeat (accent, text tones,
/// rail chrome, status LEDs) so they have a single source of truth. One-off
/// gradient and shadow stops that are purely local to a single widget's
/// "plastic" rendering are intentionally left inline where they are used —
/// naming each one centrally would add noise, not clarity.
abstract final class Palette {
  /// The app's base dark plastic surface (window background).
  static const Color background = Color(0xFF14100C);

  /// Primary interactive accent (buttons, cursors, scan spinner, active menu).
  static const Color accent = Color(0xFFEF8A24);

  /// Warning / out-of-range red.
  static const Color error = Color(0xFFFF5449);

  /// Primary text — warm cream on the dark plastic surfaces.
  static const Color textPrimary = Color(0xFFF2EDE2);

  /// Secondary / body text.
  static const Color textMuted = Color(0xFFB8B2A6);

  /// Dimmed text — hints, counters, sub-labels.
  static const Color textDim = Color(0xFF8A8578);

  /// Neutral description grey (module help text).
  static const Color textDescription = Color(0xFFAAAAAA);

  /// Light field text on darker inputs.
  static const Color fieldText = Color(0xFFCFCABF);

  /// Preset-rail text tones and border.
  static const Color railText = Color(0xFFE0E0E0);
  static const Color railMuted = Color(0xFF999999);
  static const Color railBorder = Color(0xFF444444);

  /// Chain-view icon and effect-label tones.
  static const Color chainIcon = Color(0xFFCCCCCC);
  static const Color chainEffect = Color(0xFF888888);

  /// Connection status LEDs.
  static const Color ledConnected = Color(0xFF44FF44);
  static const Color ledDisconnected = Color(0xFFFF4444);
}
