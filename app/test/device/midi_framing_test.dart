import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/midi_framing.dart';

void main() {
  test('strips the leading 8080 BLE header', () {
    final wire = MidiFraming.toWire('8080F00B0900010000000201020100F7');

    expect(wire.first, 0xF0);
    expect(wire.last, 0xF7);
    // 'F00B...F7' is 28 hex chars -> 14 bytes
    expect(wire.length, 14);
  });

  test('accepts hex without an 8080 header unchanged', () {
    final wire = MidiFraming.toWire('F0010203F7');

    expect(wire, [0xF0, 0x01, 0x02, 0x03, 0xF7]);
  });

  test('is case-insensitive', () {
    expect(MidiFraming.toWire('8080f0a1f7'), [0xF0, 0xA1, 0xF7]);
  });

  test('rejects malformed hex', () {
    expect(() => MidiFraming.toWire('8080F0A'), throwsFormatException); // odd
    expect(() => MidiFraming.toWire('ZZ'), throwsFormatException);
  });
}
