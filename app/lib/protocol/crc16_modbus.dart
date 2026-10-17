/// CRC-16/MODBUS: polynomial 0xA001 (reflected 0x8005), init 0xFFFF,
/// refIn/refOut, no final XOR (check value 0x4B37 over "123456789").
///
/// This is the container checksum embedded in a Sonicake `.clo` tone-capture:
/// computed over bytes `[12, N)` (N = the length field) and stored big-endian
/// at offset 8. Mirrors the native `tone_catch_crc_utils` used by the tool.
class Crc16Modbus {
  static const int _polynomial = 0xA001;

  static int ofBytes(List<int> bytes) => bytes.fold(0xFFFF, (crc, byte) {
    var next = crc ^ (byte & 0xFF);

    for (final _ in Iterable<int>.generate(8)) {
      next = (next & 1) != 0 ? (next >> 1) ^ _polynomial : next >> 1;
    }

    return next;
  });
}
