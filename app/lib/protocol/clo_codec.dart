import 'dart:typed_data';

import 'crc16_modbus.dart';

/// A decoded Sonicake `.clo` tone-capture (the pedal's native clone model).
///
/// The pedal plays a Wiener-Hammerstein chain built from these fields:
/// `x → FIR([arrayA]) → drive → asymmetric-saturator → FIR([arrayB]) → level →
/// DC-block([biquad])`. See `tools/re/nam/CLO_SPEC.md`.
class CloProfile {
  const CloProfile({
    required this.biquad,
    required this.gains,
    required this.arrayA,
    required this.arrayB,
  });

  /// DC-block biquad `[b0, b1, b2, a1, a2]` (a0 = 1 implied), f64.
  final List<double> biquad;

  /// `[POSMAX, NEGMAX, pos_rate, neg_rate]` — output level (g0/g1) and input
  /// drive (g2/g3) of the asymmetric exponential saturator, f32.
  final List<double> gains;

  /// Pre-filter FIR (input EQ), [CloCodec.arrayALength] taps, f32.
  final List<double> arrayA;

  /// Post-filter FIR (amp + cab response), [CloCodec.arrayBLength] taps, f32.
  final List<double> arrayB;
}

/// Reads and writes the `.clo` binary container byte-for-byte, matching the
/// official tool's converter output (verified against golden captures).
///
/// Layout (8840 bytes, little-endian scalars unless noted):
///
///   0   'VTSI'                     8   u16 CRC-16/MODBUS of [12:end] (BIG-endian)
///   4   u32 total size (8840)      20  u32 body length (8704)
///   24  f64 1.0                    64  5× f64 biquad
///   104 4× f32 gains              120  u32 0
///   124 u32 128 (arrayA len)      128  u32 128 (arrayB offset)
///   132 u32 2048 (arrayB len)     136  128× f32 arrayA
///   648 2048× f32 arrayB
class CloCodec {
  static const int totalSize = 8840;
  static const int bodyLength = 8704;
  static const int magic = 0x49535456; // 'VTSI' little-endian
  static const int arrayALength = 128;
  static const int arrayBLength = 2048;

  /// The USB upload variant truncates the post-filter to 512 taps (the pedal's
  /// runtime length), shrinking the container to 2696 bytes. See CLO_SPEC.md /
  /// tools/re/nam/clone_up.usbmon.
  static const int uploadArrayBTaps = 512;

  static const int _headerLength = 136;

  static const int _crcOffset = 8;
  static const int _crcRegionStart = 12;
  static const int _biquadOffset = 64;
  static const int _gainsOffset = 104;
  static const int _arrayAOffset = 136;
  static const int _arrayBOffset = 648;

  /// Encodes [profile] into the container, computing the CRC-16. Arrays are
  /// truncated / zero-padded to the fixed slot lengths. [arrayBTaps] selects the
  /// post-filter length: [arrayBLength] (2048) for the on-disk file, or
  /// [uploadArrayBTaps] (512) for the USB upload variant.
  static Uint8List encode(CloProfile profile, {int arrayBTaps = arrayBLength}) {
    final size = _arrayBOffset + arrayBTaps * 4;

    final buf = Uint8List(size);
    final data = ByteData.sublistView(buf);

    data.setUint32(0, magic, Endian.little);
    data.setUint32(4, size, Endian.little);
    data.setUint32(20, size - _headerLength, Endian.little);
    data.setFloat64(24, 1.0, Endian.little);

    _writeF64s(data, _biquadOffset, profile.biquad, 5);
    _writeF32s(data, _gainsOffset, profile.gains, 4);

    data.setUint32(124, arrayALength, Endian.little);
    data.setUint32(128, arrayALength, Endian.little);
    data.setUint32(132, arrayBTaps, Endian.little);

    _writeF32s(data, _arrayAOffset, profile.arrayA, arrayALength);
    _writeF32s(data, _arrayBOffset, profile.arrayB, arrayBTaps);

    final crc = Crc16Modbus.ofBytes(buf.sublist(_crcRegionStart, size));

    data.setUint16(_crcOffset, crc, Endian.big);

    return buf;
  }

  /// Decodes a `.clo` container, throwing [FormatException] on a bad magic,
  /// size, or CRC mismatch.
  static CloProfile decode(Uint8List bytes) {
    if (bytes.length != totalSize) {
      throw FormatException('expected $totalSize bytes, got ${bytes.length}');
    }

    final data = ByteData.sublistView(bytes);

    if (data.getUint32(0, Endian.little) != magic) {
      throw const FormatException('bad .clo magic (expected VTSI)');
    }

    final storedCrc = data.getUint16(_crcOffset, Endian.big);
    final crc = Crc16Modbus.ofBytes(bytes.sublist(_crcRegionStart, totalSize));

    if (storedCrc != crc) {
      throw FormatException('CRC mismatch: stored $storedCrc, computed $crc');
    }

    return CloProfile(
      biquad: _readF64s(data, _biquadOffset, 5),
      gains: _readF32s(data, _gainsOffset, 4),
      arrayA: _readF32s(data, _arrayAOffset, arrayALength),
      arrayB: _readF32s(data, _arrayBOffset, arrayBLength),
    );
  }

  static void _writeF64s(ByteData data, int offset, List<double> values, int n) {
    for (final (i, v) in values.take(n).indexed) {
      data.setFloat64(offset + i * 8, v, Endian.little);
    }
  }

  static void _writeF32s(ByteData data, int offset, List<double> values, int n) {
    for (final (i, v) in values.take(n).indexed) {
      data.setFloat32(offset + i * 4, v, Endian.little);
    }
  }

  static List<double> _readF64s(ByteData data, int offset, int n) =>
      List<double>.generate(n, (i) => data.getFloat64(offset + i * 8, Endian.little));

  static List<double> _readF32s(ByteData data, int offset, int n) =>
      List<double>.generate(n, (i) => data.getFloat32(offset + i * 4, Endian.little));
}
