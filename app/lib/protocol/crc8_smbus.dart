/// CRC-8/SMBUS (PEC): polynomial 0x07, init 0x00, no reflection, no final XOR.
/// Port of the legacy `calculateSMBusPEC`.
class Crc8Smbus {
  static const int _polynomial = 0x07;

  static int ofBytes(List<int> bytes) {
    var crc = 0;

    for (final byte in bytes) {
      crc ^= byte & 0xFF;

      for (var i = 0; i < 8; i++) {
        if (crc & 0x80 != 0) {
          crc = (crc << 1) ^ _polynomial;
        } else {
          crc <<= 1;
        }

        crc &= 0xFF;
      }
    }

    return crc;
  }

  /// Parses [hexString] (pairs of hex digits) and returns the CRC as a
  /// 2-character uppercase hex string.
  static String ofHex(String hexString) {
    final bytes = <int>[];

    for (var i = 0; i + 1 < hexString.length; i += 2) {
      bytes.add(int.parse(hexString.substring(i, i + 2), radix: 16));
    }

    return ofBytes(bytes).toRadixString(16).toUpperCase().padLeft(2, '0');
  }
}
