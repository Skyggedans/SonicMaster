import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/slider_nudge.dart';

void main() {
  test('snapToStep rounds to int for integer step, 1 decimal otherwise', () {
    expect(snapToStep(50.4, 1), 50);
    expect(snapToStep(50.6, 1), 51);
    expect(snapToStep(2.34, 0.1), 2.3);
  });

  test('nudge moves by step, clamps, snaps', () {
    expect(nudge(50, 1, 1, 0, 100), 51);
    expect(nudge(50, 1, -1, 0, 100), 49);
    expect(nudge(100, 1, 1, 0, 100), 100);
    expect(nudge(0, 1, -1, 0, 100), 0);
  });

  test('parseSliderValue parses+clamps+snaps, null on junk', () {
    expect(parseSliderValue('75', 0, 100, 1), 75);
    expect(parseSliderValue('999', 0, 100, 1), 100);
    expect(parseSliderValue('-5', 0, 100, 1), 0);
    expect(parseSliderValue('abc', 0, 100, 1), isNull);
    expect(parseSliderValue('', 0, 100, 1), isNull);
  });

  test('valueToRot maps min->0, max->sweep, mid->half', () {
    expect(valueToRot(0, 0, 100), 0);
    expect(valueToRot(100, 0, 100), 300);
    expect(valueToRot(50, 0, 100), 150);
    expect(valueToRot(5, 5, 5), 0); // degenerate range
  });

  test('dragLinearStep: up increases, down decreases, clamps to range', () {
    // travelPx 200 over range 100 => 0.5 units/px. +40px up => +20.
    expect(dragLinearStep(50, 40, 0, 100, 200), closeTo(70, 1e-9));
    expect(dragLinearStep(50, -40, 0, 100, 200), closeTo(30, 1e-9));
    expect(dragLinearStep(90, 40, 0, 100, 200), 100); // clamp high
    expect(dragLinearStep(10, -40, 0, 100, 200), 0); // clamp low
  });

  test(
    'dragLinearStep: 4x travelPx (Shift fine-tune) ~quarters the change',
    () {
      expect(
        dragLinearStep(50, 40, 0, 100, 800),
        closeTo(55, 1e-9),
      ); // +5 not +20
    },
  );

  // Parses as the compact knob editor does: a decimal comma is accepted.
  num? parseWithComma(String text, num min, num max, num step) =>
      parseSliderValue(text, min, max, step, isDecimalCommaAccepted: true);

  test('parseSliderValue can read a decimal comma at a fractional step', () {
    expect(parseWithComma('1,5', 0, 10, 0.1), 1.5);
    expect(parseWithComma('-12,5', -20, 20, 0.1), -12.5);
    expect(parseWithComma(' 2,4 ', 0, 10, 0.1), 2.4); // trimmed first
  });

  test('parseSliderValue rejects a comma at an integer step', () {
    // At an integer step a comma is a thousands separator, not a decimal one:
    // '1,500' ms must not become 1.5 (snapped to 2).
    expect(parseWithComma('1,500', 0, 1000, 1), isNull);
    expect(parseWithComma('1,5', 0, 1000, 1), isNull);
  });

  test('parseSliderValue rejects a comma unless asked to read one', () {
    // Regular (desktop) keeps today's parsing.
    expect(parseSliderValue('2,5', 0, 10, 0.1), isNull);
  });

  test('withDecimalPoint maps a lone comma and nothing else', () {
    expect(withDecimalPoint('2,5'), '2.5');
    expect(withDecimalPoint('2.5'), '2.5');
    expect(withDecimalPoint('1,2,3'), '1,2,3');
    expect(withDecimalPoint('1,234.5'), '1,234.5');
    expect(withDecimalPoint('abc'), 'abc');
  });
}
