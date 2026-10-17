import 'package:flutter/widgets.dart';

import '../theme/app_text.dart';

/// D1: the compact layout applies to any viewport narrower than 960 or shorter
/// than 600 logical px — phones in either orientation, a tablet in portrait, a
/// small browser window. Tablets in landscape and desktop windows stay
/// regular.
bool isCompactViewport(Size size) => size.width < 960 || size.height < 600;

/// Duration of the app's short UI motions (the drawer slide, its scrim, the
/// toggle knob). Shared so every motion feels the same.
const sonicMotionDuration = Duration(milliseconds: 160);

/// Easing of the app's short UI motions: the curve SonicToggle's knob slides
/// on.
const sonicMotionCurve = Cubic(0.4, 0.15, 0.3, 1);

/// The size tokens of the two layouts. Exactly two canonical const instances
/// exist ([regular], [compact]) and the constructor is private, so identity is
/// equality: compare with `identical`, never with field-by-field checks.
///
/// Every [regular] value equals the literal it replaces, so code that reads
/// [regular] renders pixel-identically to the code before it.
@immutable
class SonicMetrics {
  const SonicMetrics._({
    required this.isCompact,
    required this.topBarHeight,
    required this.minAppWidth,
    required this.topBarIconPadding,
    required this.workPadding,
    required this.chainPanelsGap,
    required this.minPanelHeight,
    required this.presetPanelWidth,
    required this.panelKnobSize,
    required this.knobCellPadding,
    required this.knobValueStyle,
    required this.knobLabelStyle,
    required this.editorHeaderPadding,
    required this.editorControlHeight,
    required this.isEffectDescriptionVisible,
    required this.footswitchSegmentPadding,
    required this.chainCardMinWidth,
    required this.chainCardMaxWidth,
    required this.chainCardPadding,
    required this.chainGripGap,
    required this.chainIconSize,
    required this.chainIconGap,
    required this.chainLedGap,
    required this.chainLedSize,
    required this.chainBadgeTop,
    required this.chainConnectorIconSize,
    required this.chainConnectorPadding,
    required this.ampBlockPadding,
    required this.dialogMargin,
    required this.dialogPadding,
  });

  /// Desktop and tablet: today's layout, pixel for pixel.
  static const regular = SonicMetrics._(
    isCompact: false,
    topBarHeight: 60,
    minAppWidth: 960,
    topBarIconPadding: EdgeInsets.all(8),
    workPadding: 12,
    chainPanelsGap: 34,
    minPanelHeight: 212,
    presetPanelWidth: 360,
    panelKnobSize: 120,
    knobCellPadding: 8,
    knobValueStyle: AppText.knobValue,
    knobLabelStyle: AppText.knobLabel,
    editorHeaderPadding: EdgeInsets.fromLTRB(16, 12, 16, 4),
    editorControlHeight: 40,
    isEffectDescriptionVisible: true,
    footswitchSegmentPadding: 16,
    chainCardMinWidth: 96,
    chainCardMaxWidth: 96,
    chainCardPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    chainGripGap: 6,
    chainIconSize: 46,
    chainIconGap: 4,
    chainLedGap: 8,
    chainLedSize: Size(48, 16),
    chainBadgeTop: 20,
    chainConnectorIconSize: 20,
    chainConnectorPadding: 2,
    ampBlockPadding: 10,
    dialogMargin: EdgeInsets.symmetric(horizontal: 40, vertical: 24),
    dialogPadding: EdgeInsets.fromLTRB(24, 22, 24, 18),
  );

  /// Phones (and a tablet in portrait): the overlay preset drawer instead of
  /// the rail, denser panels.
  static const compact = SonicMetrics._(
    isCompact: true,
    topBarHeight: 48,
    minAppWidth: 640,
    topBarIconPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    workPadding: 8,
    chainPanelsGap: 8,
    minPanelHeight: 142,
    presetPanelWidth: 194,
    panelKnobSize: 72,
    knobCellPadding: 4,
    knobValueStyle: AppText.knobValueCompact,
    knobLabelStyle: AppText.knobLabelCompact,
    editorHeaderPadding: EdgeInsets.fromLTRB(12, 4, 12, 4),
    editorControlHeight: 32,
    isEffectDescriptionVisible: false,
    footswitchSegmentPadding: 10,
    chainCardMinWidth: 54,
    chainCardMaxWidth: 96,
    chainCardPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    chainGripGap: 2,
    chainIconSize: 28,
    chainIconGap: 2,
    chainLedGap: 4,
    chainLedSize: Size(36, 12),
    chainBadgeTop: -6,
    chainConnectorIconSize: 16,
    chainConnectorPadding: 0,
    ampBlockPadding: 4,
    dialogMargin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    dialogPadding: EdgeInsets.fromLTRB(16, 12, 16, 10),
  );

  /// Whether this is the compact token set. Mode switches (rail vs drawer,
  /// title-bar variant) read this; sizes read their own tokens.
  final bool isCompact;

  /// Height of the title bar; also the compact drawer header and the burger
  /// slot.
  final double topBarHeight;

  /// The app never lays out narrower than this; a narrower viewport scrolls the
  /// whole app sideways. Regular: the desktop window minimum. Compact: the
  /// narrowest landscape Android phone, where the signal chain still fits one
  /// row.
  final double minAppWidth;

  /// Padding of the title-bar icon buttons (22-px glyphs). Regular is
  /// SonicIconButton's default (a 38x38 target); compact makes it 38x46, so
  /// the touch target fills most of the 48-px bar.
  final EdgeInsets topBarIconPadding;

  /// Padding around the work-area content, on every side; the content's
  /// minimum height is the work viewport minus twice this.
  final double workPadding;

  /// Gap between the signal chain and the two work panels below it.
  final double chainPanelsGap;

  /// Minimum height of the Preset Vol / effect-editor panels, so the Preset
  /// Vol knob (value + dial + label) always fits even when the editor has
  /// little content (e.g. "no decoded effect"). Compact: the 12-px fallback
  /// spacer, one 123-px compact cell and the panel's border (137), plus slack.
  final double minPanelHeight;

  /// Width of the Preset Vol / BPM panel: two panel-knob cells side by side
  /// plus the panel's padding and border. Fixed per mode, never derived from
  /// the panel's `stacked` state: the effect editor beside it is an Expanded,
  /// so a width that followed the layout would change the editor's width,
  /// flip whether its knobs wrap, flip `stacked`, and oscillate every frame
  /// (visible flicker). When stacked, the two knobs centre in this width.
  final double presetPanelWidth;

  /// Dial diameter of the module editor's knobs, of Preset Vol / BPM and of
  /// the rail's Master Vol. The editor and the Preset panel must use the same
  /// size: the page decides `stacked` by comparing the module knob row with
  /// 1.4x one Preset Vol cell. PanelCell's body is this plus 4, so non-knob
  /// controls centre on the dial.
  final double panelKnobSize;

  /// Padding around a KnobControl or PanelCell cell, on every side.
  final double knobCellPadding;

  /// A KnobControl's value readout and its edit field; also the height of
  /// PanelCell's reserved readout row.
  final TextStyle knobValueStyle;

  /// The caption under a KnobControl or PanelCell.
  final TextStyle knobLabelStyle;

  /// Padding of the module editor's header row (title, effect, on/off). Its
  /// horizontal inset is the control row's 8 plus [knobCellPadding], so the
  /// title lines up with the first cell; compact makes the header 4 + 32 + 4
  /// = 40 tall.
  final EdgeInsets editorHeaderPadding;

  /// Height of the editor's non-knob controls: the header effect dropdown, the
  /// select and sync-division dropdowns, the panel toggles, the IR/NAM buttons
  /// and the tap-tempo division dropdown.
  final double editorControlHeight;

  /// Whether the module editor shows the effect description under its
  /// controls.
  final bool isEffectDescriptionVisible;

  /// Horizontal padding inside each FOOT SWITCH segment (None / FS1 / FS2).
  final double footswitchSegmentPadding;

  /// The narrowest a chain card gets while the chain is kept on one row. It
  /// must stay at least 52: a selected card's inner width (this minus
  /// [chainCardPadding] and a 2-px border on each side) holds the 40-px grip.
  final double chainCardMinWidth;

  /// The widest a chain card gets, and a ModuleCard's width when none is
  /// given. Regular pins both bounds to 96.
  final double chainCardMaxWidth;

  /// Padding inside a chain card, around its grip, icon, names and LED.
  final EdgeInsets chainCardPadding;

  /// Gap between a chain card's drag grip and its icon.
  final double chainGripGap;

  /// Height of a chain card's module icon.
  final double chainIconSize;

  /// Gap between a chain card's icon and its module name.
  final double chainIconGap;

  /// Gap between a chain card's effect name and its LED.
  final double chainLedGap;

  /// Size of a chain card's on/off LED.
  final Size chainLedSize;

  /// Top offset of a chain card's FS badge (its right offset stays -4).
  /// Compact lifts it above the card's top-right corner so it never covers the
  /// 28-px icon; the overhang must stay within [workPadding], or the work
  /// area's scroll view clips it.
  final double chainBadgeTop;

  /// Size of the chevron between two chain cards.
  final double chainConnectorIconSize;

  /// Horizontal inset on each side of that chevron.
  final double chainConnectorPadding;

  /// Padding inside the amp block's dashed border.
  final double ampBlockPadding;

  /// Space between a [SonicDialog] plate and the screen edges. Compact gives
  /// back 32 px of height on a 280-393-px-tall phone.
  final EdgeInsets dialogMargin;

  /// A [SonicDialog]'s inner padding when its caller passes none.
  final EdgeInsets dialogPadding;

  /// Width of one chevron connector between two chain cards.
  double get chainConnectorWidth =>
      chainConnectorIconSize + 2 * chainConnectorPadding;

  /// The token set for a viewport of [size].
  static SonicMetrics forSize(Size size) =>
      isCompactViewport(size) ? compact : regular;

  /// The nearest [SonicMetricsScope]'s tokens, or [regular] without one, so
  /// component tests that pump a widget on its own keep today's sizes.
  static SonicMetrics of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SonicMetricsScope>()
          ?.metrics ??
      regular;
}

/// Publishes [metrics] to the subtree. SonicMasterApp installs one above the
/// Navigator, so the page and every dialog route read the same tokens.
/// Dependents rebuild only when the token set changes (a mode flip), never on
/// a resize within the same mode.
class SonicMetricsScope extends InheritedWidget {
  const SonicMetricsScope({
    super.key,
    required this.metrics,
    required super.child,
  });

  final SonicMetrics metrics;

  @override
  bool updateShouldNotify(SonicMetricsScope oldWidget) =>
      !identical(metrics, oldWidget.metrics);
}
