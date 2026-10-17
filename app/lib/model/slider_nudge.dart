/// Snaps [v] to the parameter's precision: integer [step] → int, else 1 decimal.
num snapToStep(num v, num step) => step == step.roundToDouble()
    ? v.round()
    : double.parse(v.toStringAsFixed(1));

/// Nudges [value] by one [step] in [dir] (+1 up / -1 down), clamped + snapped.
num nudge(num value, num step, int dir, num min, num max) =>
    snapToStep((value + dir * step).clamp(min, max), step);

/// Parses typed [text] to a clamped, snapped value; null when not a number.
/// With [isDecimalCommaAccepted] (compact: phone keyboards), a decimal comma
/// reads as a point at a fractional [step] ('2,5' → 2.5). At an integer step a
/// comma is a thousands separator, so '1,500' is rejected, not read as 1.5.
num? parseSliderValue(
  String text,
  num min,
  num max,
  num step, {
  bool isDecimalCommaAccepted = false,
}) {
  final trimmed = text.trim();
  final isFractional = step != step.roundToDouble();
  final v = num.tryParse(
    isDecimalCommaAccepted && isFractional
        ? withDecimalPoint(trimmed)
        : trimmed,
  );

  if (v == null) return null;

  return snapToStep(v.clamp(min, max), step);
}

/// [text] with a lone decimal comma read as a point ('2,5' → '2.5'): several
/// mobile keyboards offer only the locale's separator. Text that already has a
/// '.' or more than one ',' is returned as typed.
String withDecimalPoint(String text) =>
    !text.contains('.') && ','.allMatches(text).length == 1
    ? text.replaceFirst(',', '.')
    : text;

/// Knob rotation (deg) for [value]: 0 at [min], [sweep] at [max].
double valueToRot(num value, num min, num max, {double sweep = 300}) =>
    max == min ? 0 : ((value - min) / (max - min)) * sweep;

/// Advances a linear-drag accumulator by [deltaPx] px (up = positive =
/// increase); [travelPx] px spans the whole [min,max] range. Returns the new
/// UNSNAPPED, clamped value — snap only when emitting via [snapToStep].
double dragLinearStep(
  double accum,
  double deltaPx,
  num min,
  num max,
  double travelPx,
) => (accum + deltaPx * (max - min) / travelPx).clamp(
  min.toDouble(),
  max.toDouble(),
);
