import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/clo_codec.dart';

void main() {
  // The genuine converter output from the official tool (RR AC30 reference NAM),
  // captured under Wine. The Dart writer must reproduce it byte-for-byte.
  final golden = Uint8List.fromList(
    File('test/support/golden_ref.clo').readAsBytesSync(),
  );

  test('golden fixture is a well-formed .clo', () {
    expect(golden.length, CloCodec.totalSize);
    expect(golden.sublist(0, 4), 'VTSI'.codeUnits);
  });

  test('decode → encode reproduces the tool output byte-for-byte', () {
    final profile = CloCodec.decode(golden);

    final encoded = CloCodec.encode(profile);

    expect(encoded, orderedEquals(golden));
  });

  test('decode exposes the biquad, gains, and both FIR arrays', () {
    final profile = CloCodec.decode(golden);

    expect(profile.biquad, hasLength(5));
    expect(profile.gains, hasLength(4));
    expect(profile.arrayA, hasLength(CloCodec.arrayALength));
    expect(profile.arrayB, hasLength(CloCodec.arrayBLength));
    // DC-block biquad: b1 = -2·b0 (2nd-order Butterworth high-pass).
    expect(profile.biquad[1], closeTo(-2 * profile.biquad[0], 1e-3));
  });

  test('encode zero-pads short arrays to the fixed slot lengths', () {
    final profile = CloProfile(
      biquad: const [1, 0, 0, 0, 0],
      gains: const [0.5, 0.5, 1, 1],
      arrayA: const [1.0, 0.5],
      arrayB: const [1.0],
    );

    final bytes = CloCodec.encode(profile);
    final round = CloCodec.decode(bytes);

    expect(bytes.length, CloCodec.totalSize);
    expect(round.arrayA[0], closeTo(1.0, 1e-6));
    expect(round.arrayA[2], 0.0);
    expect(round.arrayB.sublist(1).every((v) => v == 0.0), isTrue);
  });

  test('decode rejects a corrupted CRC', () {
    final bad = Uint8List.fromList(golden)..[8] ^= 0xFF;

    expect(() => CloCodec.decode(bad), throwsFormatException);
  });
}
