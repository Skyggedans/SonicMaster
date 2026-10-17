import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/crc16_modbus.dart';

void main() {
  test('check value 0x4B37 over "123456789"', () {
    final bytes = '123456789'.codeUnits;

    expect(Crc16Modbus.ofBytes(bytes), 0x4B37);
  });

  test('empty input returns the init value 0xFFFF', () {
    expect(Crc16Modbus.ofBytes(const []), 0xFFFF);
  });

  test('masks bytes to 8 bits', () {
    expect(Crc16Modbus.ofBytes([0x141]), Crc16Modbus.ofBytes([0x41]));
  });
}
