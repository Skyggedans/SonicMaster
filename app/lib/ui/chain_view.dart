import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../model/chain_order.dart';
import '../model/footswitch_assignment.dart';
import '../model/footswitch_state.dart';
import '../model/module_icons.dart';
import '../state/data_providers.dart';
import '../state/edit_providers.dart';
import '../state/names_providers.dart';
import '../state/preset_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'led_button.dart';
import 'sonic_controls.dart';
import 'sonic_metrics.dart';

/// Per-module effect-icon tint, matching the pedal's own screen colours (kept a
/// touch more saturated than phone photos of the display, which read lighter).
/// Keyed by physical module id (0=NR … 8=RVB).
const moduleIconColor = <int, Color>{
  0: Color(0xFFFFFFFF), // NR  — white
  1: Color(0xFF5B8DEF), // FX1 — light blue
  2: Color(0xFFFF4136), // DRV — red
  3: Color(0xFFFF851B), // AMP — orange
  4: Color(0xFFFFD400), // IR  — yellow
  5: Color(0xFFA6E22E), // EQ  — lime
  6: Color(0xFF3FD6EC), // FX2 — light cyan
  7: Color(
    0xFF1570A8,
  ), // DLY — dark cyan (darker, distinct from FX2's bright cyan)
  8: Color(0xFFA45DE8), // RVB — violet
};

/// Width of one chain row: [cardCount] cards of [cardWidth], one connector
/// between each adjacent pair (inside the amp block too, so 8 for the 9-card
/// chain in any order), plus the amp block's padding on both sides when the
/// block is present. Its dashed border paints on that padding, and the drag
/// wrappers add no size.
double chainRowWidth(
  SonicMetrics metrics, {
  required double cardWidth,
  int cardCount = 9,
  bool hasAmpBlock = true,
}) =>
    cardCount * cardWidth +
    (cardCount - 1) * metrics.chainConnectorWidth +
    (hasAmpBlock ? 2 * metrics.ampBlockPadding : 0);

/// The widest whole-pixel card width that keeps [cardCount] cards on ONE row
/// of [availableWidth], clamped to the metrics' card bounds. Regular pins both
/// bounds to 96, so its cards never change; below the compact floor the chain's
/// Wrap breaks rows as before. An empty chain or an unbounded width gets the
/// widest card.
double chainCardWidth(
  SonicMetrics metrics, {
  required double availableWidth,
  required int cardCount,
  required bool hasAmpBlock,
}) {
  if (cardCount == 0 || !availableWidth.isFinite) {
    return metrics.chainCardMaxWidth;
  }

  final fixed = chainRowWidth(
    metrics,
    cardWidth: 0,
    cardCount: cardCount,
    hasAmpBlock: hasAmpBlock,
  );

  return ((availableWidth - fixed) / cardCount).floorToDouble().clamp(
    metrics.chainCardMinWidth,
    metrics.chainCardMaxWidth,
  );
}

/// One effect card in the signal chain: SVG icon, module name, effect name,
/// and an amber [LedButton] at the bottom-center for on/off. Pure presentation.
class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.iconId,
    required this.name,
    this.effect,
    required this.isOn,
    required this.isSelected,
    required this.isEnabled,
    this.footswitch = FootswitchAssignment.none,
    this.draggable = true,
    this.width,
    this.onSelect,
    this.onToggle,
  });

  final int iconId;
  final String name;
  final String? effect;
  final bool isOn;
  final bool isSelected;
  final bool isEnabled;

  /// The footswitch this module is assigned to, shown as a corner badge.
  final FootswitchAssignment footswitch;

  /// Reorderable card → show the drag-handle grip. The fixed amp-block cards
  /// aren't draggable, so their grip is hidden (its space is kept so the cards
  /// stay the same height).
  final bool draggable;

  /// The card's width; null means [SonicMetrics.chainCardMaxWidth]. ChainView
  /// passes the width that keeps the chain on one row (chainCardWidth).
  final double? width;
  final VoidCallback? onSelect;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final metrics = SonicMetrics.of(context);

    final display = Opacity(
      opacity: isOn ? 1 : 0.4,
      child: Column(
        mainAxisSize: .min,
        children: [
          SizedBox(
            height: metrics.chainIconSize,
            child: SvgPicture.asset(
              moduleIconAsset[iconId] ?? moduleIconAsset[0]!,
              theme: SvgTheme(
                currentColor: moduleIconColor[iconId] ?? Palette.chainIcon,
              ),
              fit: .contain,
            ),
          ),
          SizedBox(height: metrics.chainIconGap),
          Text(
            name,
            style: AppText.chainLabel.copyWith(color: Palette.chainIcon),
          ),
          Text(
            effect ?? '—',
            maxLines: 1,
            overflow: .ellipsis,
            style: AppText.chainSub,
          ),
        ],
      ),
    );

    final card = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onSelect,
        child: Container(
          width: width ?? metrics.chainCardMaxWidth,
          // The bottom padding lives in the LED row below (its hit area).
          padding: metrics.chainCardPadding.copyWith(bottom: 0),
          // Same "plate" as the panels: warm gradient, hairline edge, lifted by a
          // drop shadow. Selected keeps the orange outline + glow; the rest drop
          // the grey border.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF221D19), Color(0xFF14100D)],
            ),
            border: Border.all(
              width: isSelected ? 2 : 1,
              color: isSelected ? Palette.accent : const Color(0x99000000),
            ),
            boxShadow: [
              const BoxShadow(
                color: Color(0x8C000000),
                offset: Offset(0, 4),
                blurRadius: 12,
              ),
              if (isSelected)
                const BoxShadow(color: Color(0x4DFF6B35), blurRadius: 10),
            ],
          ),
          child: Column(
            mainAxisSize: .min,
            children: [
              // Drag-handle grip: an 8×2 array of tactile dots, top-centre.
              // Hidden (but space kept) on the fixed amp-block cards.
              DragGrip(isVisible: draggable),
              SizedBox(height: metrics.chainGripGap),
              display,
              // The LED row. The gap above the LED and the card's bottom
              // padding are the row's padding (identical geometry) and, in
              // compact, part of the LED's tap target: a ~36x12 LED is too
              // small for a finger. Regular leaves them inert, so taps there
              // select the card as before; so does a disabled card.
              SonicHitArea(
                padding: EdgeInsets.only(
                  top: metrics.chainLedGap,
                  bottom: metrics.chainCardPadding.bottom,
                ),
                onTap: metrics.isCompact && isEnabled ? onToggle : null,
                // A small centered 3:1 recessed button — NOT stretched across
                // the card. (LedButton's inner face has an alignment, so it
                // would otherwise expand to the full card width.)
                child: Center(
                  child: SizedBox(
                    width: metrics.chainLedSize.width,
                    child: LedButton(
                      isOn: isOn,
                      label: '',
                      height: metrics.chainLedSize.height,
                      onTap: isEnabled ? onToggle : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (footswitch == FootswitchAssignment.none) return card;

    // Float the footswitch badge over the card's right edge: a little below the
    // top-right corner in regular; in compact above the corner, clear of the
    // 28-px icon (the work padding keeps it unclipped). It lives in an outer
    // Clip.none Stack so it overlaps the edge and never participates in the
    // card's own layout.
    return Stack(
      clipBehavior: .none,
      children: [
        card,
        Positioned(
          top: metrics.chainBadgeTop,
          right: -4,
          child: _FsBadge(footswitch),
        ),
      ],
    );
  }
}

/// The little corner chip on a [ModuleCard] naming its footswitch (FS1 / FS2).
class _FsBadge extends StatelessWidget {
  const _FsBadge(this.assignment);

  final FootswitchAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final label = assignment == .fs1 ? 'FS1' : 'FS2';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: Palette.accent,
      ),
      child: Text(
        label,
        style: AppText.chainLabel.copyWith(
          color: const Color(0xFFFFFFFF),
          fontSize: 11,
          height: 1.1,
        ),
      ),
    );
  }
}

/// The signal-flow chevron drawn between adjacent cards.
class ChainConnector extends StatelessWidget {
  const ChainConnector({super.key});

  @override
  Widget build(BuildContext context) {
    final metrics = SonicMetrics.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.chainConnectorPadding),
      child: Icon(
        Icons.chevron_right,
        size: metrics.chainConnectorIconSize,
        color: const Color(0xFF666666),
      ),
    );
  }
}

/// Corner radius shared by the dashed border and its dark fill, so the fill's
/// corners round to the dashes instead of poking past them.
const double _ampBlockRadius = 12;

/// The dashed rounded border around the fixed amp block (web #fixed-chain-block).
class AmpBlockBorder extends StatelessWidget {
  const AmpBlockBorder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashPainter(),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0x26000000),
        borderRadius: BorderRadius.circular(_ampBlockRadius),
      ),
      padding: EdgeInsets.all(SonicMetrics.of(context).ampBlockPadding),
      child: child,
    ),
  );
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_ampBlockRadius),
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF555555);

    // Dashed stroke: walk each rounded-rect contour, laying a 5px dash every 9px.
    // A cursor advancing by a fixed step has no iterator form — keep imperative.
    for (final metric in (Path()..addRRect(r)).computeMetrics()) {
      var d = 0.0;

      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => false;
}

/// Assembles the module cards into a reorderable horizontal signal chain,
/// wired to the decoded preset state and edit providers.
class ChainView extends ConsumerWidget {
  const ChainView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(currentPresetStateProvider);
    final selected = ref.watch(currentSelectedEffectsProvider);
    final selectedModule = ref.watch(selectedModuleProvider);
    final isLoading = ref.watch(presetLoadingProvider);
    final data = ref.watch(dataAssetsProvider).valueOrNull;
    final userNames = ref.watch(userNamesProvider);
    final metrics = SonicMetrics.of(context);

    if (state == null) return const SizedBox.shrink();

    // Physical slot id (on/off), and the editor target (module 9 for clone amp).
    int? slotId(String m) => data?.modules.idOf(m);

    int? editId(String m) {
      final id = slotId(m);

      if (id == 3 && state.isCloneMode) return 9;

      return id;
    }

    String? effectName(String m) {
      final id = editId(m);
      final fx = id == null ? null : selected[id];

      if (fx == null || data == null) return null;

      return effectDisplayName(fx, data.effects, userNames);
    }

    ModuleCard card(String m, double width, {bool draggable = true}) {
      final isOn = state.moduleStates[m] ?? false;
      final sid = slotId(m);
      final fs = sid == null
          ? FootswitchAssignment.none
          : footswitchAssignmentOf(
              state.footswitchFs1Mask,
              state.footswitchFs2Mask,
              sid,
            );

      return ModuleCard(
        iconId: data?.modules.idOf(m) ?? 0,
        name: m,
        effect: effectName(m),
        isOn: isOn,
        isSelected: editId(m) == selectedModule,
        isEnabled: !isLoading && sid != null,
        footswitch: fs,
        draggable: draggable,
        width: width,
        onSelect: () =>
            ref.read(selectedModuleProvider.notifier).state = editId(m),
        onToggle: (isLoading || sid == null)
            ? null
            : () => toggleModule(ref, sid, !isOn),
      );
    }

    final groups = collapseChain(state.chainOrder);

    Widget cellFor(List<String> group, double cardWidth) {
      if (isAmpBlock(group)) {
        return AmpBlockBorder(
          child: Row(
            mainAxisSize: .min,
            children: [
              for (final (i, m) in group.indexed) ...[
                if (i > 0) const ChainConnector(),
                card(m, cardWidth, draggable: false),
              ],
            ],
          ),
        );
      }

      return card(group.first, cardWidth);
    }

    // Move draggable group [from] to slot [to] (adjusting for the removal).
    void moveGroup(int from, int to) {
      if (isLoading || from == to) return;

      final gs = collapseChain(state.chainOrder);
      final g = gs.removeAt(from);

      gs.insert(from < to ? to - 1 : to, g);
      reorderChain(ref, gs);
    }

    // One chain cell: the card (or amp block) with a trailing connector, made a
    // drop target. Free modules drag horizontally to reorder; the amp block is
    // fixed. Horizontal-axis affinity means a sideways drag starts the reorder
    // immediately, while a vertical drag still scrolls the work area and a plain
    // tap still selects the card / toggles its LED. (A LongPressDraggable used
    // to gate this behind a press-and-hold, which read as "can't drag".)
    Widget chainCell(int i, List<String> group, bool isLast, double cardWidth) {
      final content = Row(
        mainAxisSize: .min,
        children: [
          cellFor(group, cardWidth),
          if (!isLast) const ChainConnector(),
        ],
      );

      final child = (isAmpBlock(group) || isLoading)
          ? content
          : Draggable<int>(
              data: i,
              affinity: .horizontal,
              feedback: Opacity(opacity: 0.9, child: cellFor(group, cardWidth)),
              childWhenDragging: Opacity(opacity: 0.3, child: content),
              child: content,
            );

      return DragTarget<int>(
        key: ValueKey('chain-${group.join('-')}'),
        onWillAcceptWithDetails: (d) => !isLoading && d.data != i,
        onAcceptWithDetails: (d) => moveGroup(d.data, i),
        builder: (context, candidate, rejected) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: candidate.isNotEmpty
                ? const Color(0x22FF6B35)
                : Color(0x00000000),
          ),
          child: child,
        ),
      );
    }

    // The card width comes from the width actually available, so the
    // LayoutBuilder is there in both modes (regular's bounds are equal, so its
    // cards stay 96 and the tree keeps one shape across mode flips).
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = chainCardWidth(
          metrics,
          availableWidth: constraints.maxWidth,
          cardCount: state.chainOrder.length,
          hasAmpBlock: groups.any(isAmpBlock),
        );

        // Centered, wrapping to new rows when the width runs out (web
        // .chain-flow); compact card widths keep the chain on one row.
        return Wrap(
          alignment: .center,
          runAlignment: .center,
          crossAxisAlignment: .center,
          runSpacing: 8,
          children: [
            for (final (i, group) in groups.indexed)
              chainCell(i, group, i == groups.length - 1, cardWidth),
          ],
        );
      },
    );
  }
}
