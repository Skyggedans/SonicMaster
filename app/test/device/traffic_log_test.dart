import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/traffic_log.dart';

void main() {
  final at = DateTime.utc(2026, 7, 10, 14, 30, 15, 123);

  test('formats a frame line: ts, padded dir, byte count, uppercase hex', () {
    final line = TrafficLog.formatLine(at, 'RX', [0xF0, 0x0b, 0xa1, 0xF7]);

    expect(line, '2026-07-10T14:30:15.123Z  RX    4B  F00BA1F7');
  });

  test('pads short directions so columns align (TX vs MARK)', () {
    final rx = TrafficLog.formatLine(at, 'TX', const []);

    expect(rx, startsWith('2026-07-10T14:30:15.123Z  TX    0B  '));
  });

  test('appends a note when given (marker lines)', () {
    final line = TrafficLog.formatLine(
      at,
      'MARK',
      const [],
      note: 'enter tuner',
    );

    expect(line, endsWith('MARK  0B    enter tuner'));
  });

  test('single bytes are zero-padded to two hex digits', () {
    final line = TrafficLog.formatLine(at, 'RX', [0x00, 0x05, 0x0f]);

    expect(line, endsWith('  00050F'));
  });
}
