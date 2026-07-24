import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/tap_tempo.dart';

void main() {
  test('clampBpm clamps to [20,300] and rounds to nearest 0.5', () {
    expect(clampBpm(10), 20);
    expect(clampBpm(350), 300);
    expect(clampBpm(120.3), 120.5);
    expect(clampBpm(120.1), 120.0);
  });

  test(
    'delayMs = 60000/clampBpm * multiplier, rounded (not range-clamped)',
    () {
      expect(delayMs(120, 1.0), 500);
      expect(delayMs(120, 0.5), 250);
      expect(delayMs(120, 0.75), 375);
      expect(delayMs(120, 2.0), 1000);
      expect(delayMs(20, 2.0), 6000); // caller clamps to the Time range
    },
  );

  test('bpmFromTaps averages consecutive intervals', () {
    expect(bpmFromTaps([0, 500]), 120);
    expect(bpmFromTaps([0, 500, 1000, 1500]), 120);
    expect(bpmFromTaps([0]), isNull);
    expect(bpmFromTaps(const []), isNull);
    expect(bpmFromTaps([0, 3500]), isNull); // mean >= 3000 -> too slow
    expect(bpmFromTaps([0, 0]), isNull); // mean <= 0
  });

  test('noteDivisions are the four expected (label, multiplier) pairs', () {
    expect(noteDivisions.map((d) => d.$2).toList(), [0.5, 0.75, 1.0, 2.0]);
    expect(noteDivisions[2], ('1/4', 1.0));
  });
}
