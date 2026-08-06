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
}
