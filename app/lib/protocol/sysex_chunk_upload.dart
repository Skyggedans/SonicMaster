import 'dart:typed_data';

import 'crc8_smbus.dart';

/// Fragments a logical blob into the pedal's chunked SysEx upload transport,
/// shared byte-for-byte by the User-IR and clone-profile paths.
///
/// Each chunk is a frame
///
///   8080 F0  cc  tt  ss  ll  <2·ll payload nibbles>  F7
///
/// where every logical byte is a nibble pair (hi, lo) and `cc` is the
/// CRC-8/SMBUS of `[total, seq, len] + payload`. The `8080` prefix is the
/// BLE-MIDI timestamp header (USB framing strips it).
class SysexChunkUpload {
  /// Source bytes carried per chunk.
  static const int chunkPayloadBytes = 19;

  /// Fragments [blob] into wire chunk frames, each ready for
  /// `Transport.sendFrame`.
  static List<String> buildChunks(Uint8List blob) {
    final total = (blob.length + chunkPayloadBytes - 1) ~/ chunkPayloadBytes;

    return List.generate(total, (seq) {
      final start = seq * chunkPayloadBytes;
      final part = blob.sublist(
        start,
        (start + chunkPayloadBytes).clamp(0, blob.length),
      );

      return frame(total, seq, part);
    });
  }

  /// Builds a single `8080…F7` frame for [seq] of [total] carrying [part].
  /// Exposed for one-off control frames (e.g. the clone commit trailer).
  static String frame(int total, int seq, List<int> part) {
    final crc = Crc8Smbus.ofBytes([total, seq, part.length, ...part]);

    final bytes = <int>[
      0xF0,
      ...nibblePair(crc),
      ...nibblePair(total),
      ...nibblePair(seq),
      ...nibblePair(part.length),
      ...part.expand(nibblePair),
      0xF7,
    ];

    return '8080${hex(bytes)}';
  }

  static List<int> nibblePair(int b) => [(b >> 4) & 0x0F, b & 0x0F];

  static String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}
