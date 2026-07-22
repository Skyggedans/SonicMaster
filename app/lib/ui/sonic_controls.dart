import 'dart:math' as math;

import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_hooks/flutter_hooks.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Official UI-kit controls, faithful to `UI Kit (standalone).html`:
/// [SonicToggle] reproduces the BOOST toggle and [SonicDropdown] the MODE
/// dropdown. All boolean toggles and dropdowns in the app use these.

/// The BOOST toggle: a recessed dark track with an orange fill that fades in
/// when on and a knob that slides across. [onChanged] null → disabled/dimmed.
class SonicToggle extends StatelessWidget {
  const SonicToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 26,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Proportions taken verbatim from the kit (track 104×46, knob 36, margin 5,
    // travel 58) and scaled by [height].
    final h = height;
    final s = h / 46; // scale vs the kit's native 46px track
    final w = h * 104 / 46;
    final m = h * 5 / 46;
    final knob = h - 2 * m;
    final travel = w - knob - 2 * m;
    final isEnabled = onChanged != null;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Opacity(
        opacity: isEnabled ? 1 : 0.4,
        child: GestureDetector(
          behavior: .opaque,
          onTap: isEnabled ? () => onChanged!(!value) : null,
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                // recessed track
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(h / 2),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF14100C), Color(0xFF211C18)],
                    ),
                  ),
                ),
                // fake the inset top shadow (Flutter has no inset box-shadow)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(h / 2),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x8C000000), Color(0x00000000)],
                          stops: [0.0, 0.35],
                        ),
                      ),
                    ),
                  ),
                ),
                // orange fill — fades in when on
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(m * 0.85),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: value ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(h / 2),
                          // Vertical linear gradient (dark top -> light bottom),
                          // mirroring the off-state track's black gradient
                          // direction (#14100C -> #211C18) — reads cleaner than
                          // the old radial hotspot.
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF9C4A08),
                              Color(0xFFD5720F),
                              Color(0xFFF4972A),
                            ],
                            stops: [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // sliding knob
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 160),
                  curve: const Cubic(0.4, 0.15, 0.3, 1),
                  top: m,
                  left: value ? m + travel : m,
                  width: knob,
                  height: knob,
                  child: CustomPaint(
                    size: Size(knob, knob),
                    painter: _ToggleKnobPainter(s),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the toggle knob as a convex disc, reproducing the kit's knob shadows
/// (which are inset — Flutter has no inset box-shadow, so they're drawn as
/// blurred crescents clipped inside the circle):
///   box-shadow: inset 0 1px 2px rgba(255,255,255,.14),  // top highlight rim
///               inset 0 -3px 6px rgba(0,0,0,.8),          // bottom shadow
///               0 3px 6px rgba(0,0,0,.55);                // drop shadow
/// [s] scales the kit's native px values (46px track) to the rendered size.
class _ToggleKnobPainter extends CustomPainter {
  const _ToggleKnobPainter(this.s);

  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final circle = Rect.fromCircle(center: c, radius: r);
    // Oversized rect so the inset-shadow crescents' outer edge is far away.
    final big = Rect.fromLTRB(
      -size.width,
      -size.height,
      size.width * 2,
      size.height * 2,
    );

    // outer drop shadow: 0 3px 6px rgba(0,0,0,.55)
    canvas.drawCircle(
      c + Offset(0, 3 * s),
      r,
      Paint()
        ..color = const Color(0x8C000000)
        ..maskFilter = MaskFilter.blur(.normal, 3 * s),
    );

    // body: linear gradient #322C27 (top) -> #17130F (bottom)
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF322C27), Color(0xFF17130F)],
        ).createShader(circle),
    );

    // inset shadows live inside the disc.
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));

    // inset bottom shadow (inset 0 -3px 6px rgba(0,0,0,.8)): dark crescent along
    // the bottom inner edge — the shadow shows where the up-shifted disc isn't.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(big),
        Path()..addOval(circle.translate(0, -3 * s)),
      ),
      Paint()
        ..color = const Color(0xCC000000)
        ..maskFilter = MaskFilter.blur(.normal, 3 * s),
    );

    // inset top highlight (inset 0 1px 2px rgba(255,255,255,.14)): bright rim
    // along the top inner edge (down-shifted disc leaves the top crescent).
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(big),
        Path()..addOval(circle.translate(0, 1 * s)),
      ),
      Paint()
        ..color = const Color(0x24FFFFFF)
        ..maskFilter = MaskFilter.blur(.normal, 1 * s),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ToggleKnobPainter oldDelegate) => oldDelegate.s != s;
}

/// A recessed (concave) black well, matching the inactive [SonicToggle] body:
/// the same black vertical gradient plus inset shadows. Flutter has no inset
/// box-shadow, so the shadows are painted as blurred regions clipped inside the
/// rounded rect. [accent] optionally paints a rounded bar down the left edge.
class SonicRecess extends StatelessWidget {
  const SonicRecess({
    super.key,
    required this.child,
    this.radius = 10,
    this.padding = EdgeInsets.zero,
    this.accent,
    this.colors,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? accent;

  /// Optional top→bottom fill gradient; defaults to the black toggle-track
  /// gradient. Pass a grey pair to sink a well into a lighter surround.
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RecessPainter(radius: radius, accent: accent, colors: colors),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _RecessPainter extends CustomPainter {
  const _RecessPainter({required this.radius, this.accent, this.colors});

  final double radius;
  final Color? accent;
  final List<Color>? colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final big = Rect.fromLTRB(
      -size.width,
      -size.height,
      size.width * 2,
      size.height * 2,
    );
    Path insetRing(Offset shift) => Path.combine(
      PathOperation.difference,
      Path()..addRect(big),
      Path()..addRRect(shift == Offset.zero ? rrect : rrect.shift(shift)),
    );

    // vertical fill — black toggle-track gradient by default, or a caller grey.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors ?? const [Color(0xFF14100C), Color(0xFF211C18)],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipRRect(rrect);
    // inset 0 3px 7px rgba(0,0,0,.9): the toggle body's top recess
    canvas.drawPath(
      insetRing(const Offset(0, 3)),
      Paint()
        ..color = const Color(0xE6000000)
        ..maskFilter = const MaskFilter.blur(.normal, 3.5),
    );
    // inset 0 1px 2px rgba(0,0,0,.7)
    canvas.drawPath(
      insetRing(const Offset(0, 1)),
      Paint()
        ..color = const Color(0xB3000000)
        ..maskFilter = const MaskFilter.blur(.normal, 1),
    );
    // optional accent bar down the left edge (clipped -> rounded corners)
    if (accent != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 3, size.height),
        Paint()..color = accent!,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RecessPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.accent != accent ||
      oldDelegate.colors != colors;
}

/// The kit's PUSH button: a raised (convex) plate that presses into a recessed
/// (concave) well with an orange label while held — the same relief vocabulary
/// as the toggle knob (raised) and body (recessed). [accent] keeps the label
/// orange at rest too, for a primary/destructive action. [onPressed] null →
/// disabled/dimmed.
class SonicButton extends HookWidget {
  const SonicButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 44,
    this.minWidth = 104,
    this.isAccent = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final double minWidth;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    final isDown = useState(false);
    final isEnabled = onPressed != null;
    final s = height / 54; // kit's native button height
    final labelColor = (isDown.value || isAccent)
        ? Palette.accent
        : Palette.textPrimary;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Opacity(
        opacity: isEnabled ? 1 : 0.4,
        child: GestureDetector(
          behavior: .opaque,
          onTapDown: isEnabled ? (_) => isDown.value = true : null,
          onTapUp: isEnabled
              ? (_) {
                  isDown.value = false;
                  onPressed!();
                }
              : null,
          onTapCancel: isEnabled ? () => isDown.value = false : null,
          child: Transform.translate(
            // pressed relief drops the plate 1px into its well
            offset: Offset(0, isDown.value ? s : 0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: minWidth,
                minHeight: height,
                maxHeight: height,
              ),
              child: CustomPaint(
                painter: _SonicButtonPainter(isDown: isDown.value, s: s),
                child: Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 22 * s),
                    child: Text(
                      label,
                      style: AppText.button.copyWith(
                        fontSize: 19 * s,
                        letterSpacing: 19 * s * 0.12,
                        color: labelColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SonicButtonPainter extends CustomPainter {
  const _SonicButtonPainter({required this.isDown, required this.s});

  final bool isDown;
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(13 * s));
    final big = Rect.fromLTRB(
      -size.width,
      -size.height,
      size.width * 2,
      size.height * 2,
    );
    Path ring(Offset shift) => Path.combine(
      PathOperation.difference,
      Path()..addRect(big),
      Path()..addRRect(rrect.shift(shift)),
    );

    // up state casts a drop shadow; pressed sits flush in its well.
    if (!isDown) {
      canvas.drawRRect(
        rrect.shift(Offset(0, 3 * s)),
        Paint()
          ..color = const Color(0x80000000)
          ..maskFilter = MaskFilter.blur(.normal, 3 * s),
      );
    }

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDown
              ? const [Color(0xFF14100C), Color(0xFF201B17)]
              : const [Color(0xFF2A2521), Color(0xFF17130F)],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipRRect(rrect);
    if (isDown) {
      // recessed: inset 0 3px 7px .9 + inset 0 1px 2px .7
      canvas.drawPath(
        ring(Offset(0, 3 * s)),
        Paint()
          ..color = const Color(0xE6000000)
          ..maskFilter = MaskFilter.blur(.normal, 3.5 * s),
      );
      canvas.drawPath(
        ring(Offset(0, 1 * s)),
        Paint()
          ..color = const Color(0xB3000000)
          ..maskFilter = MaskFilter.blur(.normal, 1 * s),
      );
    } else {
      // convex: inset 0 -3px 6px .8 (bottom) + inset 0 1px 2px .12 (top rim)
      canvas.drawPath(
        ring(Offset(0, -3 * s)),
        Paint()
          ..color = const Color(0xCC000000)
          ..maskFilter = MaskFilter.blur(.normal, 3 * s),
      );
      canvas.drawPath(
        ring(Offset(0, 1 * s)),
        Paint()
          ..color = const Color(0x1FFFFFFF)
          ..maskFilter = MaskFilter.blur(.normal, 1 * s),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SonicButtonPainter oldDelegate) =>
      oldDelegate.isDown != isDown || oldDelegate.s != s;
}

/// Knob diameter used across the editor's panel rows. Non-knob controls
/// ([PanelCell]) reuse it to center their body on the knob's center.
const double panelKnobSize = 120;

/// A non-knob control (toggle / dropdown / button / readout) laid out to match
/// [KnobControl]'s cell so panels line up: an empty top row the height of the
/// knob's value readout, then a body region the height of the knob with
/// [control] centered (its center on the knob's center), then [label] in the
/// knob's label style. Used by the module editor and the DLY tap-tempo row.
class PanelCell extends StatelessWidget {
  const PanelCell({super.key, required this.control, this.label = ''});

  final Widget control;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: .min,
        children: [
          const Text(' ', style: AppText.knobValue), // reserve readout height
          // A Column that fills the knob-body height and centers its single
          // child puts the control's center on the knob's center — while
          // shrink-wrapping width (a bare Center would expand to panel width).
          SizedBox(
            height: panelKnobSize + 4,
            child: Column(mainAxisAlignment: .center, children: [control]),
          ),
          Text(label.toUpperCase(), style: AppText.knobLabel),
        ],
      ),
    );
  }
}

/// The shared pop-up shell: a transparent [Dialog] over a [SonicSurface] plate
/// + transparent [Material], matching the dropdown menus / BLE picker. All
/// dialogs use this so pop-ups share one look.
class SonicDialog extends StatelessWidget {
  const SonicDialog({
    super.key,
    required this.child,
    this.maxWidth = 460,
    this.padding = const EdgeInsets.fromLTRB(24, 22, 24, 18),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SonicSurface(radius: 16, padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Presents [builder] as a modal over a dimmed barrier — the Material-free
/// replacement for `showDialog`. Uses `showGeneralDialog` (from the widgets
/// layer), so it needs no `Material` ancestor or `MaterialLocalizations`.
Future<T?> showSonicDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'dismiss',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, _, _) => builder(context),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// One entry in a [SonicDropdown] / [SonicSegmented].
typedef SonicItem<T> = ({T value, String label});

/// The EQ segmented control: a rounded bar of equal segments. The active
/// segment reads pressed/sunken (dark gradient, orange text); inactive segments
/// read raised (lighter gradient, light text). [onChanged] null → disabled.
/// [width] fixes the bar width (segments split it equally); null → segments
/// size to their labels.
class SonicSegmented<T> extends StatelessWidget {
  const SonicSegmented({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.height = 34,
    this.width,
    this.isExpanded = false,
    this.disabledValues = const {},
  });

  final T value;
  final List<SonicItem<T>> segments;
  final ValueChanged<T>? onChanged;
  final double height;
  final double? width;

  /// Fill the available width (segments split it equally). [width] implies this.
  final bool isExpanded;

  /// Segment values that are individually greyed out and non-tappable while the
  /// bar as a whole stays enabled (e.g. an already-claimed footswitch).
  final Set<T> disabledValues;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;
    final isFilled = width != null || isExpanded;
    final segmentWidgets = [
      for (final (i, seg) in segments.indexed)
        _Segment(
          label: seg.label,
          isActive: seg.value == value,
          hasDivider: i > 0,
          isEnabled: isEnabled && !disabledValues.contains(seg.value),
          isDimmed: isEnabled && disabledValues.contains(seg.value),
          onTap: isEnabled && !disabledValues.contains(seg.value)
              ? () => onChanged!(seg.value)
              : null,
        ),
    ];

    final children = isFilled
        ? [for (final s in segmentWidgets) Expanded(child: s)]
        : segmentWidgets;

    Widget bar = ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Row(mainAxisSize: isFilled ? .max : .min, children: children),
    );

    if (width != null) bar = SizedBox(width: width, child: bar);

    return Opacity(
      opacity: isEnabled ? 1 : 0.45,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              offset: Offset(0, 3),
              blurRadius: 6,
            ),
          ],
        ),
        child: bar,
      ),
    );
  }
}

/// One segment of a [SonicSegmented] bar. Active reads pressed/sunken (dark
/// gradient, orange text); inactive reads raised (lighter gradient, light text).
class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.isActive,
    required this.hasDivider,
    required this.isEnabled,
    required this.isDimmed,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final bool hasDivider;
  final bool isEnabled;
  final bool isDimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: .opaque,
        onTap: onTap,
        child: Container(
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isActive
                  ? const [Color(0xFF14100C), Color(0xFF201B17)]
                  : const [Color(0xFF2A2521), Color(0xFF17130F)],
            ),
            border: hasDivider
                ? const Border(
                    left: BorderSide(color: Color(0x8C000000), width: 1),
                  )
                : null,
          ),
          // scaleDown shrinks a label that would otherwise overflow its (equal)
          // segment slice — e.g. "Pocket Master" against "Auto"/"Smart Box" —
          // instead of clipping it. Labels that already fit are left untouched.
          child: FittedBox(
            fit: .scaleDown,
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              style: AppText.segmentLabel.copyWith(
                color: isDimmed
                    ? Palette.textDim
                    : isActive
                    ? Palette.accent
                    : Palette.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The MODE dropdown: a raised pill that opens a gradient menu of options with
/// a selected-highlight. [width] fixes the trigger + menu width; when null the
/// trigger sizes to content and the menu matches its measured width.
class SonicDropdown<T> extends HookWidget {
  const SonicDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width,
    this.isEnabled = true,
    this.height = 40,
  });

  final T? value;
  final List<SonicItem<T>> items;
  final ValueChanged<T> onChanged;
  final double? width;
  final bool isEnabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final controller = useMemoized(() => OverlayPortalController(), const []);
    final link = useMemoized(() => LayerLink(), const []);
    final triggerKey = useMemoized(() => GlobalKey(), const []);
    final isOpen = useState(false);

    final label = items.isEmpty
        ? ''
        : items
              .firstWhere((it) => it.value == value, orElse: () => items.first)
              .label;

    void close() {
      controller.hide();
      isOpen.value = false;
    }

    void toggle() {
      if (!isEnabled) return;

      if (controller.isShowing) {
        controller.hide();
      } else {
        controller.show();
      }

      isOpen.value = controller.isShowing;
    }

    return CompositedTransformTarget(
      link: link,
      child: OverlayPortal(
        controller: controller,
        overlayChildBuilder: (context) => _DropdownMenu<T>(
          link: link,
          triggerKey: triggerKey,
          items: items,
          value: value,
          width: width,
          onSelected: (v) {
            onChanged(v);
            close();
          },
          onDismiss: close,
        ),
        child: _DropdownTrigger(
          triggerKey: triggerKey,
          label: label,
          isOpen: isOpen.value,
          width: width,
          isEnabled: isEnabled,
          height: height,
          onTap: toggle,
        ),
      ),
    );
  }
}

class _DropdownTrigger extends StatelessWidget {
  const _DropdownTrigger({
    required this.triggerKey,
    required this.label,
    required this.isOpen,
    required this.width,
    required this.isEnabled,
    required this.height,
    required this.onTap,
  });

  final GlobalKey triggerKey;
  final String label;
  final bool isOpen;
  final double? width;
  final bool isEnabled;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget trigger = Container(
      key: triggerKey,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C2621), Color(0xFF17130F)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            offset: Offset(0, 3),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: width == null ? .min : .max,
        mainAxisAlignment: .spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: .ellipsis,
              style: AppText.controlLabel.copyWith(color: Palette.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedRotation(
            turns: isOpen ? 0.5 : 0,
            duration: const Duration(milliseconds: 180),
            child: const Icon(
              Icons.keyboard_arrow_down,
              size: 22,
              color: Palette.accent,
            ),
          ),
        ],
      ),
    );

    if (width != null) {
      trigger = SizedBox(width: width, child: trigger);
    }

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Opacity(
        opacity: isEnabled ? 1 : 0.45,
        child: GestureDetector(onTap: onTap, child: trigger),
      ),
    );
  }
}

class _DropdownMenu<T> extends StatelessWidget {
  const _DropdownMenu({
    required this.link,
    required this.triggerKey,
    required this.items,
    required this.value,
    required this.width,
    required this.onSelected,
    required this.onDismiss,
  });

  final LayerLink link;
  final GlobalKey triggerKey;
  final List<SonicItem<T>> items;
  final T? value;
  final double? width;
  final ValueChanged<T> onSelected;
  final VoidCallback onDismiss;

  // Widest item label + padding, but never narrower than the trigger — so a
  // content-sized menu never ellipsizes an option (its width previously just
  // tracked the trigger, truncating longer names).
  double _contentWidth(double minWidth) {
    final maxLabel = items.fold(0.0, (widest, it) {
      final tp = TextPainter(
        text: TextSpan(text: it.label, style: AppText.menuItem),
        textDirection: .ltr,
        maxLines: 1,
      )..layout();

      return math.max(widest, tp.width);
    });

    return math.max(minWidth, maxLabel + 32); // 14*2 padding + margin
  }

  @override
  Widget build(BuildContext context) {
    final box = triggerKey.currentContext?.findRenderObject() as RenderBox?;
    final trigW = box?.size.width ?? 220;
    final menuWidth = width ?? _contentWidth(trigW);

    return Stack(
      children: [
        // outside-tap barrier
        Positioned.fill(
          child: GestureDetector(behavior: .opaque, onTap: onDismiss),
        ),
        CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: menuWidth,
              child: SonicSurface(
                radius: 11,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: .min,
                      children: [
                        for (final it in items)
                          _SonicMenuItem(
                            label: it.label,
                            isSelected: it.value == value,
                            onTap: () => onSelected(it.value),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SonicMenuItem extends StatelessWidget {
  const _SonicMenuItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: .opaque,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected ? const Color(0x24E07405) : Color(0x00000000),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: .ellipsis,
            style: AppText.menuItem.copyWith(
              color: isSelected
                  ? const Color(0xFFF2AC52)
                  : const Color(0xFFD8D3C8),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dropdown-menu backdrop — a dark gradient panel with a hairline border and
/// drop shadow. Reused for popup surfaces (the dropdown menu and dialogs) so
/// they all share the same "plate".
class SonicSurface extends StatelessWidget {
  const SonicSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(6),
    this.radius = 13,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: .antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF221D19), Color(0xFF14100D)],
        ),
        border: Border.all(color: const Color(0x99000000)),
        boxShadow: const [
          BoxShadow(
            color: Color(0xB3000000),
            offset: Offset(0, 12),
            blurRadius: 26,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A Material-free loading spinner: a rotating accent arc. Replaces
/// `CircularProgressIndicator` / `LinearProgressIndicator` in the kit.
class SonicSpinner extends HookWidget {
  const SonicSpinner({super.key, this.size = 26, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 900),
    );

    useEffect(() {
      controller.repeat();

      return null;
    }, const []);

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CustomPaint(
          painter: _SpinnerPainter(
            turns: controller.value,
            color: color ?? Palette.accent,
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({required this.turns, required this.color});

  final double turns;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.shortestSide * 0.12;

    canvas.drawArc(
      rect.deflate(stroke),
      turns * 2 * math.pi,
      math.pi * 1.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) =>
      oldDelegate.turns != turns || oldDelegate.color != color;
}

/// A Material-free icon button: a tappable [Icon] with no ripple. Dims when
/// [onPressed] is null.
class SonicIconButton extends StatelessWidget {
  const SonicIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 22,
    this.color,
    this.padding = const EdgeInsets.all(8),
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: .opaque,
        onTap: onPressed,
        child: Opacity(
          opacity: isEnabled ? 1 : 0.4,
          child: Padding(
            padding: padding,
            child: Icon(icon, size: size, color: color ?? Palette.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// A drag-handle grip: an 8×2 array of small tactile dots. Shared by the
/// reorderable module cards and the dev-console resize divider so both read the
/// same. [isVisible] false keeps the footprint but paints no dots (fixed cards).
class DragGrip extends StatelessWidget {
  const DragGrip({super.key, this.isVisible = true});

  final bool isVisible;

  @override
  Widget build(BuildContext context) {
    Widget dot() => Container(
      width: 2,
      height: 2,
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: .circle,
        color: isVisible ? const Color(0xFF6E675D) : const Color(0x00000000),
      ),
    );

    Widget row() =>
        Row(mainAxisSize: .min, children: List.generate(8, (_) => dot()));

    return Column(mainAxisSize: .min, children: [row(), row()]);
  }
}
