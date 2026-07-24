import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/ir_upload_frame.dart';

// Golden vectors from the live capture of the official tool uploading
// `impulse_512_44100.wav` into User IR 3 (slot 2, name "impulse_51"). At 44100
// Hz the device stores the samples verbatim, so the encoder must reproduce the
// tool's frames byte-for-byte. See tools/re/ and the protocol spec.
void main() {
  // impulse: sample 0 = round(32767/32768 × fullScale) = 8388351, rest silent.
  final samples = [8388351, ...List.filled(511, 0)];

  test('blob: header (magic/slot/name) + int24 sample 0', () {
    final blob = IrUploadFrame.buildBlob(
      slot: 2,
      name: 'impulse_51',
      samples: samples,
    );

    expect(blob.length, 2122);
    expect(
      _hex(blob.sublist(0, 20)),
      '1121000000000200100A696D70756C73655F3531',
    );
    // 8388351 = 0x7FFEFF stored int32 little-endian.
    expect(blob.sublist(74, 78), [0xFF, 0xFE, 0x7F, 0x00]);
  });

  test('chunks reproduce the captured upload byte-for-byte', () {
    final blob = IrUploadFrame.buildBlob(
      slot: 2,
      name: 'impulse_51',
      samples: samples,
    );

    final chunks = IrUploadFrame.buildChunks(blob);

    expect(chunks.length, 112);
    expect(
      chunks.first,
      '8080F0070E070000000103010102010000000000000000000200000100000A0609060D07000705060C07030605050F0305F7',
    );
    expect(
      chunks[1],
      '8080F00C0C0700000101030301000000000000000000000000000000000000000000000000000000000000000000000000F7',
    );
    expect(
      chunks[110],
      '8080F00E000700060E01030000000000000000000000000000000000000000000000000000000000000000000000000000F7',
    );
    // Last chunk carries the 13-byte remainder (len 0x0D), so it is shorter.
    expect(
      chunks.last,
      '8080F005050700060F000D0000000000000000000000000000000000000000000000000000F7',
    );
  });

  test('slot maps to byte[6] (User IR 5 = slot 4)', () {
    final blob = IrUploadFrame.buildBlob(
      slot: 4,
      name: 'x',
      samples: samples,
    );

    expect(blob[6], 4);
  });

  test('name is truncated to 10 chars and non-ASCII stripped', () {
    final blob = IrUploadFrame.buildBlob(
      slot: 0,
      name: 'verylongname_beyond',
      samples: samples,
    );

    expect(blob[9], IrUploadFrame.nameMaxChars);
    expect(
      String.fromCharCodes(blob.sublist(10, 20)),
      'verylongna',
    );
  });

  test('rejects a sample count other than 512', () {
    expect(
      () => IrUploadFrame.buildBlob(slot: 0, name: 'x', samples: const [0, 0]),
      throwsArgumentError,
    );
  });

  // Golden vectors from live captures of the tool renaming/clearing User IR 3.
  test('rename chunks reproduce the captured frames byte-for-byte', () {
    final chunks = IrUploadFrame.buildChunks(
      IrUploadFrame.buildRenameBlob(slot: 2, name: 'abcde12345'),
    );

    expect(chunks, [
      '8080F00A0500020000010301010202000200000100000A0601060206030604060503010302030303040305000000000000F7',
      '8080F0000A000200010003000000000000F7',
    ]);
  });

  test('name-field-length byte is a fixed 0x0A even for a short name', () {
    // The clear command carries 0x0A there with no name at all, so it is a
    // fixed field, not the actual name length — the device rejects a shorter
    // value. The name itself is still just "Imm" + NUL padding.
    final rename = IrUploadFrame.buildRenameBlob(slot: 3, name: 'Imm');

    expect(rename[5], 0x0A);
    expect(rename.sublist(6, 9), 'Imm'.codeUnits);
    expect(rename.sublist(9, 22), everyElement(0));

    final upload = IrUploadFrame.buildBlob(
      slot: 0,
      name: 'Imm',
      samples: samples,
    );

    expect(upload[9], 0x0A);
  });

  test('clear chunk reproduces the captured frame byte-for-byte', () {
    final chunks = IrUploadFrame.buildChunks(
      IrUploadFrame.buildClearBlob(slot: 2),
    );

    expect(chunks, ['8080F0080D00010000000601010203000200000100000AF7']);
  });
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
