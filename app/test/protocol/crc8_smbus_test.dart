import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/crc8_smbus.dart';

void main() {
  test('standard CRC-8/SMBUS check value: "123456789" -> 0xF4', () {
    // ASCII "123456789" = bytes 0x31..0x39
    const ascii = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39];

    expect(Crc8Smbus.ofBytes(ascii), 0xF4);
  });

  test('ofHex parses hex and returns 2-char uppercase hex', () {
    expect(Crc8Smbus.ofHex('313233343536373839'), 'F4');
  });

  test('empty input -> 0x00 seed', () {
    expect(Crc8Smbus.ofBytes(const []), 0x00);
    expect(Crc8Smbus.ofHex(''), '00');
  });
}
