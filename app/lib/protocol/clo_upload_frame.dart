import 'dart:typed_data';

import 'clo_codec.dart';
import 'sysex_chunk_upload.dart';

/// Encodes a clone-profile (`.clo`) upload for the Sonicake pedal, per the
/// reverse-engineered protocol (`tools/re/nam/PROTOCOL.md`) and the golden
/// capture `tools/re/nam/clone_up.usbmon`.
///
/// A logical blob — `magic 1125 | reserved | slot | reserved | 0x0F |
/// 64-byte name | upload-.clo` — is fragmented over the same chunked SysEx
/// transport as User-IR ([SysexChunkUpload]). Differs from IR only in the blob
/// magic (`1125` vs `1121`), the name-capacity byte (`0x0F` vs `0x0A`), and the
/// payload (a 2696-byte upload-`.clo`, whose post-filter is truncated to
/// [CloCodec.uploadArrayBTaps] taps, instead of 512 int24 samples).
class CloUploadFrame {
  /// Clones show a 15-char name (byte 9 of the blob header).
  static const int nameMaxChars = 15;

  static const int _nameFieldChars = 0x0F;
  static const int _nameOffset = 10;
  static const int _nameFieldLength = 64;
  static const int _dataOffset = _nameOffset + _nameFieldLength; // 74
  static const int _slotOffset = 6;

  /// Commit trailer sent after the last chunk (payload `1224`).
  static final String commitFrame = SysexChunkUpload.frame(1, 0, const [
    0x12,
    0x24,
  ]);

  /// Builds the logical upload blob for [slot] (0-based clone slot), [name]
  /// (ASCII, truncated to [nameMaxChars]), and the tone [profile]. The slot is
  /// carried at byte [_slotOffset] — confirmed by diffing two captures (slot 0
  /// → byte 0x00, slot 2 → byte 0x02, only that byte differs).
  static Uint8List buildBlob({
    required int slot,
    required String name,
    required CloProfile profile,
  }) {
    final clo = CloCodec.encode(profile, arrayBTaps: CloCodec.uploadArrayBTaps);
    final nameBytes = _asciiName(name);

    final blob = Uint8List(_dataOffset + clo.length);
    blob[0] = 0x11;
    blob[1] = 0x25;
    blob[_slotOffset] = slot;
    blob[9] = _nameFieldChars;
    blob.setRange(_nameOffset, _nameOffset + nameBytes.length, nameBytes);
    blob.setRange(_dataOffset, _dataOffset + clo.length, clo);

    return blob;
  }

  static const int _renameNameField = 16;

  /// Blob for renaming clone [slot] (0-based) to [name] — magic `1126`, a
  /// 22-byte payload (6-byte header + 16-byte name field), no `.clo` data.
  /// Reproduces the tool's clone-rename frames byte-for-byte.
  static Uint8List buildRenameBlob({required int slot, required String name}) {
    final nameBytes = _asciiName(name);

    final blob = Uint8List(6 + _renameNameField);
    blob[0] = 0x11;
    blob[1] = 0x26;
    blob[2] = slot;
    blob[5] = _nameFieldChars;
    blob.setRange(6, 6 + nameBytes.length, nameBytes);

    return blob;
  }

  /// Blob for clearing clone [slot] (0-based) — magic `1127`, a fixed 6-byte
  /// payload, a single chunk. Reproduces the tool's clone-clear frame.
  static Uint8List buildClearBlob({required int slot}) =>
      Uint8List.fromList([0x11, 0x27, slot, 0x00, 0x00, _nameFieldChars]);

  /// Fragments [blob] into wire chunk frames (each `8080…F7`).
  static List<String> buildChunks(Uint8List blob) =>
      SysexChunkUpload.buildChunks(blob);

  static Uint8List _asciiName(String name) {
    final codes = name.codeUnits
        .where((c) => c >= 0x20 && c < 0x7F)
        .take(nameMaxChars)
        .toList();

    return Uint8List.fromList(codes);
  }
}
