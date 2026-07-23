import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'; // re-exports Matrix4 (vector_math)
import 'package:flutter_hooks/flutter_hooks.dart';

import '../model/slider_nudge.dart';
import '../theme/app_text.dart';
import 'sonic_field.dart';

/// A rotary knob reproducing the pedal's VOL/VALUE scalloped encoder. Angular
/// drag / scroll / double-tap-to-type edit the [value]; reports via [onChanged].
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
  });

  // Pixels of vertical drag that span the whole [min,max] range. One tunable:
  // lower = more sensitive. Shift multiplies it (fine-tune).
  static const double _travelPx = 250;

  final num value;
  final num min;
  final num max;
  final num step;
  final String label;
  final String? unit;
  final ValueChanged<num> onChanged;
  final bool isEnabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isEditing = useState(false);
    final dragValue = useState<double>(0); // unsnapped accumulator (no drift)
    final controller = useTextEditingController();

    void panStart(DragStartDetails d) => dragValue.value = value.toDouble();

    void panUpdate(DragUpdateDetails d) {
      if (!isEnabled) return;

      // Vertical drag: up increases (d.delta.dy is +down, so negate). Shift =
      // fine-tune (~4× slower); read per-update so mid-drag toggling is smooth.
      final travel = HardwareKeyboard.instance.isShiftPressed
          ? _travelPx * 4
          : _travelPx;

      dragValue.value = dragLinearStep(
        dragValue.value,
        -d.delta.dy,
        min,
        max,
        travel,
      );

      onChanged(snapToStep(dragValue.value, step));
    }

    void onSignal(PointerSignalEvent e) {
      if (!isEnabled || e is! PointerScrollEvent || e.scrollDelta.dy == 0) {
        return;
      }

      onChanged(nudge(value, step, e.scrollDelta.dy < 0 ? 1 : -1, min, max));
    }

    void startEdit() {
      controller.text = '$value';
      isEditing.value = true;
    }

    void commit() {
      final v = parseSliderValue(controller.text, min, max, step);

      if (isEditing.value) isEditing.value = false;

      if (v != null) onChanged(v);
    }

    void cancel() {
      if (isEditing.value) isEditing.value = false;
    }

    final knob = MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: SizedBox(
        key: const Key('knob'),
        width: size,
        height: size,
        child: Listener(
          onPointerSignal: onSignal,
          child: GestureDetector(
            onPanStart: isEnabled ? panStart : null,
            onPanUpdate: isEnabled ? panUpdate : null,
            child: CustomPaint(
              painter: _KnobPainter(valueToRot(value, min, max)),
            ),
          ),
        ),
      ),
    );

    final readout = isEditing.value
        ? CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): cancel,
            },
            child: SonicField(
              controller: controller,
              autofocus: true,
              textAlign: .center,
              style: AppText.knobValue,
              isRecessed: false,
              padding: EdgeInsets.zero,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onSubmitted: (_) => commit(),
              onTapOutside: (_) => commit(),
            ),
          )
        : GestureDetector(
            onDoubleTap: isEnabled ? startEdit : null,
            child: Text('$value${unit ?? ''}', style: AppText.knobValue),
          );

    // A vertical cell — value on top, knob, name below — so cells sit side by
    // side in a Wrap like the knobs on a hardware unit.
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: .min,
        children: [
          SizedBox(
            width: size,
            child: Center(child: readout),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: knob,
          ),
          if (label.isNotEmpty)
            Text(label.toUpperCase(), style: AppText.knobLabel),
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
