/// Formats a numeric parameter value into the string key used by the device's
/// `parameters` command table: whole numbers (incl. negative) as plain integers
/// (`"5"`, `"-50"`), fractional values as one-decimal (`"0.1"`).
///
/// Robust to float noise: a value within 1e-6 of a whole number formats as that
/// integer (so `49.9999999` → `"50"`, not `"50.0"`), and a `-0.0`-style result
/// is normalized to `"0.0"`.
String formatParamValueKey(num v) {
  final d = v.toDouble();
  final rounded = d.roundToDouble();

  if ((d - rounded).abs() < 1e-6) {
    return rounded.toInt().toString(); // int has no -0, so "-0.0" -> "0"
  }

  final s = d.toStringAsFixed(1);

  return s == '-0.0' ? '0.0' : s;
}
