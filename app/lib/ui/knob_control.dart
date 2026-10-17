import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'; // re-exports Matrix4 (vector_math)
import 'package:flutter_hooks/flutter_hooks.dart';

import '../model/slider_nudge.dart';
import 'sonic_field.dart';
import 'sonic_metrics.dart';

/// A rotary knob reproducing the pedal's VOL/VALUE scalloped encoder. Vertical
/// drag / scroll / double-tap-to-type edit the [value]; reports via [onChanged].
///
/// Pointer kinds get their own recognizers, so a knob shares input with the
/// scroll views around it: a mouse or trackpad pans it as on desktop, a touch
/// or stylus drag turns it (see [isHoldToTurnOnTouch]), and a mouse-wheel tick
/// over it nudges it without also scrolling the page. A trackpad swipe on the
/// web scrolls the page and nudges the knob, as before.
class KnobControl extends HookWidget {
  const KnobControl({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.label,
    required this.onChanged,
    this.unit,
    this.isEnabled = true,
    this.size = 120,
    this.isHoldToTurnOnTouch = false,
  });

  // Pixels of vertical drag that span the whole [min,max] range. One tunable:
  // lower = more sensitive. Shift multiplies it (fine-tune).
  static const double _travelPx = 250;

  /// The pointers that turn a knob by a vertical drag (or a hold, then a drag)
  /// instead of a pan: fingers and pens, plus unknown kinds.
  static const Set<PointerDeviceKind> _touchDevices = {
    .touch,
    .stylus,
    .invertedStylus,
    .unknown,
  };

  /// How long a finger rests on a hold-to-turn knob before it turns.
  static const Duration _holdToTurnDelay = Duration(milliseconds: 200);

  final num value;
  final num min;
  final num max;
  final num step;
  final String label;
  final String? unit;
  final ValueChanged<num> onChanged;
  final bool isEnabled;
  final double size;

  /// Touch only: the knob turns after a 200-ms hold instead of on the first
  /// drag, so a flick that starts on it scrolls the list it sits in. For knobs
  /// inside scrolling lists that drive live output levels (the drawer's Master
  /// Vol, the Settings knobs). Mouse and trackpad are unaffected.
  final bool isHoldToTurnOnTouch;

  @override
  Widget build(BuildContext context) {
    final isEditing = useState(false);
    final dragValue = useState<double>(0); // unsnapped accumulator (no drift)
    // The hold-to-turn drag's last offset (dy); null until its first move.
    final holdDy = useRef<double?>(null);
    final controller = useTextEditingController();
    final editorFocus = useFocusNode();
    final metrics = SonicMetrics.of(context);

    // One step of vertical travel, shared by every pointer kind: up increases
    // ([dy] is +down, so negate). Shift = fine-tune (~4× slower); read
    // per-update so mid-drag toggling is smooth.
    void turnBy(double dy) {
      if (!isEnabled) return;

      final travel = HardwareKeyboard.instance.isShiftPressed
          ? _travelPx * 4
          : _travelPx;

      dragValue.value = dragLinearStep(dragValue.value, -dy, min, max, travel);
      onChanged(snapToStep(dragValue.value, step));
    }

    void dragStart(DragStartDetails d) => dragValue.value = value.toDouble();

    void dragUpdate(DragUpdateDetails d) => turnBy(d.delta.dy);

    void holdStart(LongPressStartDetails d) {
      dragValue.value = value.toDouble();
      holdDy.value = null;
    }

    // A long press reports its offset from the press point, not a delta. That
    // offset includes the finger's drift while it rested (up to the touch
    // slop), so the first move after the hold only sets the baseline: the
    // drift never turns the knob.
    void holdUpdate(LongPressMoveUpdateDetails d) {
      final dy = d.offsetFromOrigin.dy;
      final last = holdDy.value;

      holdDy.value = dy;

      if (last != null) turnBy(dy - last);
    }

    void onSignal(PointerSignalEvent e) {
      if (!isEnabled || e is! PointerScrollEvent || e.scrollDelta.dy == 0) {
        return;
      }

      final direction = e.scrollDelta.dy < 0 ? 1 : -1;

      // The web sends a trackpad two-finger swipe as scroll signals (native
      // sends pan-zoom). Keep today's path for it: nudge without claiming the
      // signal, so a scroll view that can move still scrolls. Firefox reports
      // a trackpad as a mouse, so there a swipe acts as a wheel.
      if (e.kind == .trackpad) {
        onChanged(nudge(value, step, direction, min, max));

        return;
      }

      // Through the resolver: the knob is the innermost claimant, so it wins
      // the tick and an enclosing scroll view (the work area, the drawer or
      // Settings list) no longer scrolls on the same tick.
      GestureBinding.instance.pointerSignalResolver.register(
        e,
        (_) => onChanged(nudge(value, step, direction, min, max)),
      );
    }

    // Touch, stylus and unknown pointers. Default: a vertical drag. It has the
    // scroll view's own 18-px slop, and the knob, the innermost recognizer,
    // sees each move first, so a drag that starts on the knob turns it instead
    // of scrolling the page (the pan needs 36 px and always lost on touch).
    // Hold-to-turn: a 200-ms long press instead; a quick flick moves past the
    // slop first and goes to the scroll view. Only the recognizer differs.
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    final touchGestures = <Type, GestureRecognizerFactory>{
      if (isHoldToTurnOnTouch)
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                duration: _holdToTurnDelay,
                supportedDevices: _touchDevices,
              ),
              (recognizer) => recognizer
                ..gestureSettings = gestureSettings
                ..onLongPressStart = isEnabled ? holdStart : null
                ..onLongPressMoveUpdate = isEnabled ? holdUpdate : null,
            )
      else
        VerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer(
                supportedDevices: _touchDevices,
              ),
              (recognizer) => recognizer
                ..gestureSettings = gestureSettings
                ..onStart = isEnabled ? dragStart : null
                ..onUpdate = isEnabled ? dragUpdate : null,
            ),
    };

    void startEdit() {
      final text = '$value';

      // Compact (phones): open with the whole value selected, so the first
      // keystroke replaces it; a phone has no mouse and no selection toolbar
      // to select it by hand. selectAllOnFocus can't do it: the editor
      // autofocuses, and the SDK skips select-all for that internal focus.
      // Regular keeps today's caret after the value.
      controller.value = TextEditingValue(
        text: text,
        selection: metrics.isCompact
            ? TextSelection(baseOffset: 0, extentOffset: text.length)
            : TextSelection.collapsed(offset: text.length),
      );
      isEditing.value = true;
    }

    void commit() {
      // Compact (phones): a decimal comma from the keyboard reads as a point.
      final v = parseSliderValue(
        controller.text,
        min,
        max,
        step,
        isDecimalCommaAccepted: metrics.isCompact,
      );

      if (isEditing.value) isEditing.value = false;

      if (v != null) onChanged(v);
    }

    void cancel() {
      if (isEditing.value) isEditing.value = false;
    }

    // Compact (phones): an editor that loses its focus commits. Closing the
    // drawer or showing the rotate prompt takes focus away without a tap, so
    // the tap-outside commit never fires. Regular keeps today's behaviour.
    // Re-subscribed every build, so it calls the current commit; isEditing
    // guards the blur that follows a Done (which committed already).
    useEffect(() {
      void onFocusChange() {
        if (metrics.isCompact && isEditing.value && !editorFocus.hasFocus) {
          commit();
        }
      }

      editorFocus.addListener(onFocusChange);

      return () => editorFocus.removeListener(onFocusChange);
    });

    final knob = MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: SizedBox(
        key: const Key('knob'),
        width: size,
        height: size,
        child: Listener(
          onPointerSignal: onSignal,
          // Mouse and trackpad keep today's pan: a precise pointer turns the
          // knob after 2 px, and a native trackpad two-finger swipe (pan-zoom,
          // 36-px pan slop) still loses to the scroll view's 18 px, so it
          // scrolls the page. The web sends that swipe as scroll signals,
          // which onSignal handles.
          child: GestureDetector(
            supportedDevices: const {.mouse, .trackpad},
            onPanStart: isEnabled ? dragStart : null,
            onPanUpdate: isEnabled ? dragUpdate : null,
            child: RawGestureDetector(
              gestures: touchGestures,
              child: CustomPaint(
                painter: _KnobPainter(valueToRot(value, min, max)),
              ),
            ),
          ),
        ),
      ),
    );

    // The readout row: the dial's width, the value centred in it.
    final readout = isEditing.value
        ? SizedBox(
            width: size,
            child: Center(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): cancel,
                },
                child: SonicField(
                  controller: controller,
                  focusNode: editorFocus,
                  autofocus: true,
                  textAlign: .center,
                  style: metrics.knobValueStyle,
                  isRecessed: false,
                  padding: EdgeInsets.zero,
                  // Compact (phones): the number pad, signed where the range
                  // is, and no autocorrect or suggestion strip over a number.
                  // Regular keeps today's keyboard and entry options.
                  keyboardType: metrics.isCompact
                      ? numericKeyboardType(isSigned: min < 0)
                      : const TextInputType.numberWithOptions(decimal: true),
                  // The SDK default on the web and desktop, where the app
                  // runs: a re-tap after the field lost focus selects the
                  // value again.
                  selectAllOnFocus: true,
                  autocorrect: !metrics.isCompact,
                  enableSuggestions: !metrics.isCompact,
                  onSubmitted: (_) => commit(),
                  onTapOutside: (_) => commit(),
                ),
              ),
            ),
          )
        : GestureDetector(
            // Compact (touch): the whole row takes the double-tap, not just
            // the digits (~16x21 px on a phone). Regular keeps today's
            // digits-only target.
            behavior: metrics.isCompact ? .opaque : .deferToChild,
            onDoubleTap: isEnabled ? startEdit : null,
            child: SizedBox(
              width: size,
              child: Center(
                child: Text(
                  '$value${unit ?? ''}',
                  style: metrics.knobValueStyle,
                ),
              ),
            ),
          );

    // A vertical cell — value on top, knob, name below — so cells sit side by
    // side in a Wrap like the knobs on a hardware unit.
    return Padding(
      padding: EdgeInsets.all(metrics.knobCellPadding),
      child: Column(
        mainAxisSize: .min,
        children: [
          readout,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: knob,
          ),
          if (label.isNotEmpty)
            Text(label.toUpperCase(), style: metrics.knobLabelStyle),
        ],
      ),
    );
  }
}

/// Paints the scalloped encoder: fixed body/face/highlight + 9 orbiting drops.
/// Only [rot] (degrees) changes with the value. Reproduces the design model.
class _KnobPainter extends CustomPainter {
  _KnobPainter(this.rot);
  final double rot;

  static const _count = 9;
  // Teardrop in a 24x32 design-unit box, point at top, round bottom (r=12).
  static final Path _drop = Path()
    ..moveTo(12, 10)
    ..cubicTo(17, 15, 24, 15, 24, 20)
    ..arcToPoint(
      const Offset(0, 20),
      radius: const Radius.circular(12),
      largeArc: true,
    )
    ..cubicTo(0, 15, 7, 15, 12, 10)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final k = s / 250.0; // design units → px

    // body
    final bodyR = 0.744 * s / 2;
    // Drop shadow to lift the knob off the background — larger than the
    // dropdown's so the knob reads as physically raised. Drawn behind the
    // (opaque) body, so only the halo around the rim shows.
    const shadow = BoxShadow(
      color: Color(0x99000000),
      offset: Offset(0, 7),
      blurRadius: 16,
    );
    canvas.drawCircle(
      c + shadow.offset,
      bodyR,
      Paint()
        ..color = shadow.color
        ..maskFilter = MaskFilter.blur(.normal, shadow.blurSigma),
    );
    final bodyRect = Rect.fromCircle(center: c, radius: bodyR);
    canvas.drawCircle(
      c,
      bodyR,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.0, -0.12),
          radius: 0.72,
          colors: [
            Color(0xFF322C23),
            Color(0xFF241F18),
            Color(0xFF120F0B),
            Color(0xFF0A0806),
          ],
          stops: [0, 0.52, 0.86, 1.0],
        ).createShader(bodyRect),
    );

    // face
    final faceR = 0.592 * s / 2;
    canvas.drawCircle(
      c,
      faceR,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.1, -0.24),
          radius: 0.6,
          colors: [Color(0xFF35302A), Color(0xFF2B261F), Color(0xFF211C16)],
          stops: [0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: faceR)),
    );

    // 9 orbiting drops — shape rotates outward, shading stays screen-vertical.
    final r = 0.312 * s;

    for (var i = 0; i < _count; i++) {
      final angle = i * (360 / _count) + rot;
      final rad = angle * math.pi / 180;
      final m = Matrix4.translationValues(c.dx, c.dy, 0)
        ..multiply(Matrix4.rotationZ(rad))
        ..multiply(Matrix4.translationValues(0, -r, 0))
        ..multiply(Matrix4.diagonal3Values(k, k, 1))
        ..multiply(Matrix4.translationValues(-12, -16, 0));
      final path = _drop.transform(m.storage);
      final b = path.getBounds();
      // subtle drop shadow
      canvas.drawPath(
        path.shift(Offset(0, 1 * k)),
        Paint()..color = const Color(0x80000000),
      );
      canvas.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF070503), Color(0xFF16110C), Color(0xFF4A4437)],
            stops: [0, 0.45, 1.0],
          ).createShader(b),
      );
    }

    // fixed soft highlight
    canvas.drawCircle(
      c,
      bodyR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.28, -0.44),
          radius: 0.5,
          colors: [
            Color(0xFFFFFFFF).withValues(alpha: 0.10),
            Color(0xFFFFFFFF).withValues(alpha: 0.0),
          ],
          stops: const [0, 0.62],
        ).createShader(bodyRect),
    );
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.rot != rot;
}
