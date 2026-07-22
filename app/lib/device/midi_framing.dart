import 'dart:typed_data';

/// Adapts stored command hex to the USB-MIDI wire form.
class MidiFraming {
  /// Strips a leading `8080` BLE header (if present) and returns the remaining
  /// `F0 … F7` bytes. Throws [FormatException] on malformed hex.
  static Uint8List toWire(String frameHex) {
    var hex = frameHex.toUpperCase();

    if (hex.startsWith('8080')) hex = hex.substring(4);

    if (hex.length.isOdd) {
      throw const FormatException('hex string has odd length');
    }

    return Uint8List.fromList(
      List.generate(hex.length ~/ 2, (i) {
        final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);

        if (byte == null) {
          throw FormatException('invalid hex byte at $i', hex);
        }

        return byte;
      }),
    );
  }
}
