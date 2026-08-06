import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/ble_framing.dart';

void main() {
  test('toWire keeps the 8080 header verbatim', () {
    expect(
      BleFraming.toWire('8080F0000900010000000201020401F7'),
      Uint8List.fromList([
        0x80, 0x80, 0xF0, 0x00, 0x09, 0x00, 0x01, 0x00, 0x00, 0x00, //
        0x02, 0x01, 0x02, 0x04, 0x01, 0xF7,
      ]),
    );
  });

  test('toF0Led strips a leading 8080 (and anything before F0)', () {
    final packet = Uint8List.fromList([0x80, 0x80, 0xF0, 0x11, 0x22, 0xF7]);

    expect(
      BleFraming.toF0Led(packet),
      Uint8List.fromList([0xF0, 0x11, 0x22, 0xF7]),
    );
  });

  test('toF0Led passes an already-F0-led packet through', () {
    final packet = Uint8List.fromList([0xF0, 0x11, 0xF7]);

    expect(BleFraming.toF0Led(packet), packet);
  });

  test('toF0Led passes a packet with no F0 through unchanged', () {
    final packet = Uint8List.fromList([0x80, 0x80]);

    expect(BleFraming.toF0Led(packet), packet);
  });
}
