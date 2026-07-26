import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/inbound_pipeline.dart';
import 'package:sonicmaster/protocol/inbound_message.dart';

Uint8List bytesOfHex(String hex) {
  return Uint8List.fromList(
    List<int>.generate(
      hex.length ~/ 2,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );
}

void main() {
  test(
    'classifies a single-packet frame (preset MODIFIED, wire form)',
    () async {
      // wire form (no 8080): total nibble (bytes[3..4]) = 1 -> single packet
      final wire = Stream.fromIterable([
        bytesOfHex('F0070A000100000003010204050001F7'),
      ]);

      final msgs = await classifyInbound(wire).toList();

      expect(msgs, hasLength(1));
      expect(msgs.single, isA<PresetModifiedMessage>());
    },
  );

  test('reassembles a multi-packet response into one DataFrame', () async {
    // total = 2 (bytes[3..4] = 0x00,0x02); two packets, payloads AA / BB.
    Uint8List pkt(int current, int payload) => Uint8List.fromList([
      0xF0,
      0x01,
      0x02,
      0x00,
      0x02,
      0x00,
      current,
      0x00,
      0x00,
      payload,
      0xF7,
    ]);

    final msgs = await classifyInbound(
      Stream.fromIterable([pkt(0, 0xAA), pkt(1, 0xBB)]),
    ).toList();

    // Only the completing (second) packet yields a message.
    expect(msgs, hasLength(1));
    expect(msgs.single, isA<DataFrame>());
    expect((msgs.single as DataFrame).hex.contains('AABB'), isTrue);
  });

  test('skips short / non-SysEx noise without killing the pipeline', () async {
    final msgs = await classifyInbound(
      Stream.fromIterable([
        Uint8List.fromList([0xFE]), // Active Sensing (System Real-Time)
        Uint8List.fromList([0xF8]), // Clock
        Uint8List.fromList([0xF0, 0x01, 0x02]), // truncated, too short
        bytesOfHex('F0070A000100000003010204050001F7'), // valid single-packet
      ]),
    ).toList();

    // Only the valid frame classifies; the noise is skipped, not fatal.
    expect(msgs, hasLength(1));
    expect(msgs.single, isA<PresetModifiedMessage>());
  });

  test(
    'a completing multi-packet that is too short is dropped, not fatal',
    () async {
      // pkt0 valid (total=2, cur=0); pkt1 completes but is too short to hold a
      // payload slice -> reassembler throws internally -> swallowed, pipeline lives.
      final pkt0 = Uint8List.fromList([
        0xF0,
        0x01,
        0x02,
        0x00,
        0x02,
        0x00,
        0x00,
        0x00,
        0x00,
        0xAA,
        0xF7,
      ]);

      final tooShort1 = Uint8List.fromList([
        0xF0,
        0x01,
        0x02,
        0x00,
        0x02,
        0x00,
        0x01,
        0xF7,
      ]);

      final valid = bytesOfHex('F0070A000100000003010204050001F7');
      final msgs = await classifyInbound(
        Stream.fromIterable([pkt0, tooShort1, valid]),
      ).toList();

      expect(msgs, hasLength(1));
      expect(msgs.single, isA<PresetModifiedMessage>());
    },
  );
}
