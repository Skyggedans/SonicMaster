import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/multi_packet_reassembler.dart';

// Build a synthetic F0-started packet with the given counters and payload.
List<int> packet({
  required int total,
  required int current,
  required List<int> payload,
}) {
  return [
    0xF0, 0x01, 0x02, // start + mfr id
    (total >> 4) & 0xF, total & 0xF, // total packets (nibble-packed)
    (current >> 4) & 0xF, current & 0xF, // current packet
    0x00, // index 7 (padding)
    // index 8 (padding) then payload starts at index 9:
    0x00,
    ...payload,
    0xF7,
  ];
}

void main() {
  test('single-packet input reassembles immediately', () {
    final r = MultiPacketReassembler();
    final out = r.addPacket(
      packet(total: 1, current: 0, payload: [0xAB, 0xCD]),
    );

    expect(out, isNotNull);
    expect(out!.startsWith('8080F0'), isTrue);
    expect(out.endsWith('F7'), isTrue);
    expect(out.contains('ABCD'), isTrue);
  });

  test(
    'multi-packet reassembles only when all packets arrive, out of order',
    () {
      final r = MultiPacketReassembler();
      // total = 2; deliver current=1 first, then current=0
      final first = r.addPacket(
        packet(total: 2, current: 1, payload: [0x22, 0x22]),
      );

      expect(first, isNull); // incomplete

      final done = r.addPacket(
        packet(total: 2, current: 0, payload: [0x11, 0x11]),
      );

      expect(done, isNotNull);

      // payloads concatenated in packet order (0 then 1): 1111 then 2222
      final payloadRegion = done!.substring(0, done.length - 2); // drop F7

      expect(payloadRegion.contains('11112222'), isTrue);
    },
  );

  test(
    'single-packet passthrough preserves the raw frame (no reconstruction)',
    () {
      final r = MultiPacketReassembler();
      // total nibbles 0,0 -> total 0 (<=1); byte[7]=0xAA is a non-template reserved
      // byte that reconstruction would wipe but passthrough must preserve.
      final raw = [
        0xF0,
        0x01,
        0x02,
        0x00,
        0x00,
        0x00,
        0x00,
        0xAA,
        0x00,
        0x77,
        0x88,
        0xF7,
      ];

      expect(r.addPacket(raw), '8080F0010200000000AA007788F7');
    },
  );

  test('two concurrent multi-packet responses stay isolated', () {
    final r = MultiPacketReassembler();

    // Response A: total=2 (id "0_2"); Response B: total=3 (id "0_3"), interleaved.
    expect(r.addPacket(packet(total: 2, current: 0, payload: [0xA0])), isNull);
    expect(r.addPacket(packet(total: 3, current: 0, payload: [0xB0])), isNull);
    expect(r.addPacket(packet(total: 3, current: 1, payload: [0xB1])), isNull);

    final a = r.addPacket(packet(total: 2, current: 1, payload: [0xA1]));

    expect(a, isNotNull);
    expect(a!.contains('A0A1'), isTrue);
    expect(a.contains('B0'), isFalse);

    final b = r.addPacket(packet(total: 3, current: 2, payload: [0xB2]));

    expect(b, isNotNull);
    expect(b!.contains('B0B1B2'), isTrue);
    expect(b.contains('A0'), isFalse);
  });
}
