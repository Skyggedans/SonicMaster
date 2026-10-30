import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/clo_codec.dart';
import 'package:sonicmaster/protocol/clo_upload_frame.dart';

void main() {
  // Golden vectors from the live capture of the official tool uploading the
  // reference NAM's .clo into a spare clone slot (name "ref_wavene").
  // clone_up.usbmon → clone_upload_golden.json. USB frames have no 8080 prefix,
  // so the encoder's output is compared with "8080" stripped.
  final golden =
      jsonDecode(
            File('test/support/clone_upload_golden.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  final goldenChunks = (golden['upload_chunks'] as List).cast<String>();
  final goldenTrailer = (golden['trailer'] as List).cast<String>();

  final profile = CloCodec.decode(
    Uint8List.fromList(File('test/support/golden_ref.clo').readAsBytesSync()),
  );

  String usb(String frame) =>
      frame.startsWith('8080') ? frame.substring(4) : frame;

  test('upload blob: magic 1125, name-capacity 0x0F, VTSI payload at 74', () {
    final blob = CloUploadFrame.buildBlob(
      slot: 0,
      name: 'ref_wavene',
      profile: profile,
    );

    expect(blob[0], 0x11);
    expect(blob[1], 0x25);
    expect(blob[9], 0x0F);
    expect(blob.sublist(10, 20), 'ref_wavene'.codeUnits);
    // Payload is the 2696-byte upload .clo (post-filter truncated to 512 taps).
    expect(blob.sublist(74, 78), 'VTSI'.codeUnits);
    expect(blob.length, 74 + 2696);
  });

  test('chunks reproduce the captured upload byte-for-byte (146 frames)', () {
    final blob = CloUploadFrame.buildBlob(
      slot: 0,
      name: 'ref_wavene',
      profile: profile,
    );

    final chunks = CloUploadFrame.buildChunks(blob).map(usb).toList();

    expect(chunks, hasLength(goldenChunks.length));
    expect(chunks, orderedEquals(goldenChunks));
  });

  test('commit trailer reproduces the captured 1224 frame', () {
    expect(usb(CloUploadFrame.commitFrame), goldenTrailer.single);
  });

  test('slot byte is at blob[6] (0-based)', () {
    final b0 = CloUploadFrame.buildBlob(slot: 0, name: 'x', profile: profile);
    final b2 = CloUploadFrame.buildBlob(slot: 2, name: 'x', profile: profile);

    expect(b0[6], 0);
    expect(b2[6], 2);
  });

  test('rename / clear reproduce the captured frames byte-for-byte', () {
    final rc =
        jsonDecode(
              File(
                'test/support/clone_rename_clear_golden.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    final rename = CloUploadFrame.buildChunks(
      CloUploadFrame.buildRenameBlob(slot: 0, name: 'renamed1'),
    ).map(usb).toList();

    final clear = CloUploadFrame.buildChunks(
      CloUploadFrame.buildClearBlob(slot: 2),
    ).map(usb).toList();

    expect(rename, orderedEquals((rc['rename'] as List).cast<String>()));
    expect(clear, orderedEquals((rc['clear'] as List).cast<String>()));
  });

  test('slot 2 reproduces the second-slot capture byte-for-byte', () {
    // Golden: the tool uploading the same .nam into User Profile 3 (slot 2).
    final s2 =
        jsonDecode(
              File(
                'test/support/clone_upload_slot2_golden.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    final chunks = CloUploadFrame.buildChunks(
      CloUploadFrame.buildBlob(slot: 2, name: 'ref_wavene', profile: profile),
    ).map(usb).toList();

    expect(chunks, orderedEquals((s2['upload_chunks'] as List).cast<String>()));
  });
}
