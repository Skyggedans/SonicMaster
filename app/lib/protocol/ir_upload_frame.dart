import 'dart:typed_data';

import 'sysex_chunk_upload.dart';

/// Encodes a User-IR upload for the Sonicake Smart Box, per the reverse-
/// engineered protocol in
/// `docs/superpowers/specs/2026-07-16-user-ir-upload-protocol.md`.
///
/// A logical blob — `magic 1121 | reserved | slot | reserved | 0x10 | nameLen |
/// 64-byte name | 512 × int24 (LE) samples` — is fragmented into
/// [_chunkPayloadBytes]-byte chunks. Each chunk is a SysEx frame
///
///   8080 F0  cc cc  tt tt  ss ss  ll ll  <2·ll payload nibbles>  F7
///
/// where every field is a nibble pair (hi, lo → one byte) and `cc` is the
/// CRC-8/SMBUS ([Crc8Smbus]) of the logical bytes `[total, seq, len] + payload`.
/// The `8080` prefix is the BLE-MIDI timestamp header (USB framing strips it),
/// matching every other stored command frame.
class IrUploadFrame {
  /// Device native IR rate — a 44100 input is stored verbatim; other rates are
  /// resampled by the device, so the host should resample to this first.
  static const int deviceRate = 44100;

  /// Fixed IR length (taps) the device stores.
  static const int deviceTaps = 512;

  /// int24 signed full scale (a full-scale DC input clamps here).
  static const int fullScale = (1 << 23) - 1;

  /// The pedal shows 10-char names; the tool truncates the file name to this.
  static const int nameMaxChars = 10;

  static const int _nameFieldLength = 64;
  static const int _nameOffset = 10;
  static const int _sampleOffset = _nameOffset + _nameFieldLength; // 74
  static const int _byte8 = 0x10;

  /// Fixed name-field-length byte the pedal expects (0x0A = 10-char capacity),
  /// NOT the actual name length: the clear command carries it with no name, and
  /// every captured rename/upload used a full 10-char name. Sending the real
  /// (shorter) length makes the device reject the command.
  static const int _nameFieldChars = 0x0A;

  /// Builds the logical blob for [slot] (0-based, 0..4 = User IR 1..5), [name]
  /// (ASCII, truncated to [nameMaxChars]), and exactly [deviceTaps] int24
  /// [samples].
  static Uint8List buildBlob({
    required int slot,
    required String name,
    required List<int> samples,
  }) {
    if (samples.length != deviceTaps) {
      throw ArgumentError.value(
        samples.length,
        'samples',
        'must be exactly $deviceTaps',
      );
    }

    final nameBytes = _asciiName(name);

    final blob = Uint8List(_sampleOffset + samples.length * 4);
    blob[0] = 0x11;
    blob[1] = 0x21;
    blob[6] = slot;
    blob[8] = _byte8;
    blob[9] = _nameFieldChars;
    blob.setRange(_nameOffset, _nameOffset + nameBytes.length, nameBytes);

    final data = ByteData.sublistView(blob);

    for (final (i, s) in samples.indexed) {
      data.setInt32(_sampleOffset + i * 4, _clampInt24(s), Endian.little);
    }

    return blob;
  }

  static const int _renameNameField = 16;

  /// Blob for renaming [slot] (0-based) to [name] — magic `1122`, a 22-byte
  /// payload (6-byte header + 16-byte name field), no sample data. Fragments
  /// into 2 chunks. Reproduces the official tool's rename frames byte-for-byte.
  static Uint8List buildRenameBlob({required int slot, required String name}) {
    final nameBytes = _asciiName(name);

    final blob = Uint8List(6 + _renameNameField);
    blob[0] = 0x11;
    blob[1] = 0x22;
    blob[2] = slot;
    blob[4] = _byte8;
    blob[5] = _nameFieldChars;
    blob.setRange(6, 6 + nameBytes.length, nameBytes);

    return blob;
  }

  /// Blob for clearing [slot] (0-based) — magic `1123`, a fixed 6-byte payload,
  /// a single chunk. Reproduces the official tool's clear frame byte-for-byte.
  static Uint8List buildClearBlob({required int slot}) =>
      Uint8List.fromList([0x11, 0x23, slot, 0x00, _byte8, 0x0A]);

  /// Fragments [blob] into wire chunk frames (each `8080…F7`, ready for
  /// `Transport.sendFrame`). For a 2122-byte blob this yields 112 frames.
  static List<String> buildChunks(Uint8List blob) =>
      SysexChunkUpload.buildChunks(blob);

  static int _clampInt24(int v) =>
      v < -fullScale ? -fullScale : (v > fullScale ? fullScale : v);

  static Uint8List _asciiName(String name) {
    final codes = name.codeUnits
        .where((c) => c >= 0x20 && c < 0x7F)
        .take(nameMaxChars)
        .toList();

    return Uint8List.fromList(codes);
  }
}
