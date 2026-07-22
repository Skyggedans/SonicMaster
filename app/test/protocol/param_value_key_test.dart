import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/param_value_key.dart';

void main() {
  test('whole numbers format as plain integers', () {
    expect(formatParamValueKey(0), '0');
    expect(formatParamValueKey(50), '50');
    expect(formatParamValueKey(100), '100');
    expect(formatParamValueKey(-50), '-50');
    expect(formatParamValueKey(5.0), '5'); // whole double -> no decimal
  });

  test('fractional values format with one decimal', () {
    expect(formatParamValueKey(0.1), '0.1');
    expect(formatParamValueKey(9.9), '9.9');
    expect(formatParamValueKey(0.30000000000000004), '0.3'); // float noise
  });

  test('near-whole float noise snaps to an integer, not "50.0"', () {
    expect(formatParamValueKey(49.999999999994), '50');
    expect(formatParamValueKey(-49.999999999994), '-50');
  });

  test('negative near-zero does not produce "-0.0"', () {
    expect(formatParamValueKey(-0.03), '0.0');
    expect(formatParamValueKey(-0.0), '0');
  });
}
