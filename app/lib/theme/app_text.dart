import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Named text-style tokens for the app.
///
/// Rule: never build a `TextStyle` from scratch — start from one of these tokens
/// and `.copyWith` only the deltas (a per-state color, a runtime-scaled size).
/// Tokens omit `color` where the call site sets it from state (active/disabled,
/// in-range/out-of-range); they bake a color only where the original style did.
///
/// The display font is Oswald; tokens that render in the branded display face
/// carry `fontFamily: 'Oswald'` so they stay correct even outside a Material
/// `DefaultTextStyle` (canvas / TextPainter). The two dialog tokens deliberately
/// use the default font, matching the existing dialog chrome.
abstract final class AppText {
  static const String _display = 'Oswald';

  /// Section header on the preset rail.
  static const TextStyle railHeader = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    letterSpacing: 0.5,
  );

  /// LED / toggle button caption.
  static const TextStyle ledLabel = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 13,
    letterSpacing: 1,
  );

  /// Segmented-control segment label.
  static const TextStyle segmentLabel = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    letterSpacing: 1.4,
  );

  /// Dropdown trigger / select-parameter label (wide tracking).
  static const TextStyle controlLabel = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    letterSpacing: 1.6,
  );

  /// Module / panel title.
  static const TextStyle moduleTitle = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    letterSpacing: 0.8,
  );

  /// Selected preset name in the browser header.
  static const TextStyle presetTitle = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    letterSpacing: 0.5,
  );

  /// Dropdown menu item.
  static const TextStyle menuItem = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    letterSpacing: 1.3,
  );

  /// Push-button label. Size/tracking are scaled per instance:
  /// `AppText.button.copyWith(fontSize: 19 * s, letterSpacing: 19 * s * 0.12)`.
  static const TextStyle button = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 19,
    letterSpacing: 19 * 0.12,
  );

  /// Effect block label in the chain view (bold, tight).
  static const TextStyle chainLabel = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.bold,
    fontSize: 12,
    letterSpacing: 0.5,
  );

  /// Small effect sub-label in the chain view.
  static const TextStyle chainSub = TextStyle(
    fontFamily: _display,
    fontSize: 10,
    color: Palette.chainEffect,
  );

  /// Connection well status label.
  static const TextStyle connectionLabel = TextStyle(
    fontFamily: _display,
    fontSize: 14,
    color: Palette.railText,
  );

  /// Tap-tempo BPM readout.
  static const TextStyle bpm = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 18,
    color: Palette.textPrimary,
  );

  /// Large tap-tempo BPM display (color set per in/out-of-range state).
  static const TextStyle bpmDisplay = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 22,
  );

  /// KnobControl / PanelCell value readout (12pt base × 1.5).
  static const TextStyle knobValue = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 18,
    color: Palette.textPrimary,
  );

  /// KnobControl / PanelCell caption under the knob (11pt base × 1.5).
  static const TextStyle knobLabel = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w500,
    fontSize: 16.5,
    letterSpacing: 0.8,
    color: Palette.textMuted,
  );

  /// Module help / description text.
  static const TextStyle moduleDescription = TextStyle(
    color: Palette.textDescription,
    fontSize: 13,
    height: 1.4,
  );

  /// Device-list row title.
  static const TextStyle deviceRowTitle = TextStyle(
    color: Palette.textPrimary,
    fontSize: 16,
  );

  /// Device-list row subtitle.
  static const TextStyle deviceRowSub = TextStyle(
    color: Palette.textDim,
    fontSize: 12,
  );

  /// Dialog title.
  static const TextStyle dialogTitle = TextStyle(
    fontFamily: _display,
    color: Palette.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  /// Dialog body copy.
  static const TextStyle dialogBody = TextStyle(
    fontFamily: _display,
    color: Palette.textMuted,
    fontSize: 14,
    height: 1.4,
  );

  /// Text-field input text.
  static const TextStyle input = TextStyle(color: Palette.textPrimary);

  /// Text-field label.
  static const TextStyle inputLabel = TextStyle(color: Palette.textMuted);

  /// Text-field hint / counter / faint helper.
  static const TextStyle inputHint = TextStyle(color: Palette.textDim);

  /// Monospaced log line (dev console).
  static const TextStyle monoLog = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
  );

  /// Emphasised section label (dev console header).
  static const TextStyle boldLabel = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.bold,
  );
}
