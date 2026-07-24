import 'dart:typed_data';

/// Adapts stored command hex / BLE-MIDI notifications for the BLE transport.
/// Over BLE-MIDI a frame keeps its `8080` header on the wire (unlike USB, which
/// strips it), and a received notification is `8080 F0 … F7`.
class BleFraming {
  /// Stored command hex -> wire bytes, verbatim (the `8080` header stays).
  static Uint8List toWire(String frameHex) {
    final hex = frameHex.toUpperCase();

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

  /// A BLE-MIDI notification -> an F0-led SysEx packet: drop everything before
  /// the first `0xF0` (the `8080` timestamp header), so `classifyInbound` (which
  /// requires an F0-led packet) consumes it exactly like a USB packet. Packets
  /// already F0-led, or with no `0xF0`, pass through unchanged.
  static Uint8List toF0Led(Uint8List packet) {
    final i = packet.indexOf(0xF0);

    return i > 0 ? Uint8List.sublistView(packet, i) : packet;
  }
}
