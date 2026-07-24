import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/modules.dart';
import 'package:sonicmaster/protocol/preset_state_decoder.dart';
import '../fixtures/preset_state_dumps.dart';

void main() {
  final modules = Modules.fromJson(
    jsonDecode(File('assets/data/modules.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  final decoder = PresetStateDecoder(modules);

  test('decodes U01 (real capture): volume 60, default order, states', () {
    final s = decoder.decode(u01StateDump)!;

    expect(s.isCloneMode, isFalse);
    expect(s.presetVolume, 60);
    // Real captured value: both fixtures were taken at the default tempo. This
    // proves the marker is found and the 16-bit LE read lands; non-default
    // values are covered by the live round-trip in integration_test.
    expect(s.presetBpm, 120);
    expect(s.chainOrder, [
      'NR',
      'FX1',
      'DRV',
      'AMP',
      'IR',
      'EQ',
      'FX2',
      'DLY',
      'RVB',
    ]);
    expect(s.moduleStates, {
      'NR': true,
      'FX1': false,
      'DRV': true,
      'AMP': true,
      'IR': true,
      'EQ': true,
      'FX2': false,
      'DLY': true,
      'RVB': true,
    });
  });

  test('decodes U02 (real capture): differs only in volume (70)', () {
    final s = decoder.decode(u02StateDump)!;

    expect(s.presetVolume, 70);
    expect(s.presetBpm, 120);
    expect(s.isCloneMode, isFalse);
    expect(s.chainOrder.first, 'NR');
    expect(s.moduleStates['DRV'], isTrue);
    expect(s.moduleStates['FX1'], isFalse);
  });

  test(
    'decodes footswitch bitmasks from the dump tail (16-bit LE, bit=module)',
    () {
      // Each mask is a bitmask, bit M = module M reacts to that switch. Values
      // verified against real captures — note FS2 groups DLY(7) + RVB(8), which a
      // low-nibble-only reader would miss (bit 7 = high nibble, bit 8 = 2nd byte).
      final u01 = decoder.decode(u01StateDump)!;

      expect(u01.footswitchFs1Mask, 0x0004); // DRV (bit 2)
      expect(u01.footswitchFs2Mask, 0x0180); // DLY (bit 7) + RVB (bit 8)
      expect((u01.footswitchFs2Mask >> 7) & 1, 1, reason: 'DLY on FS2');
      expect((u01.footswitchFs2Mask >> 8) & 1, 1, reason: 'RVB on FS2');

      expect(
        decoder.decode(p12StateDump)!.footswitchFs1Mask,
        0x0006,
      ); // FX1+DRV
      expect(
        decoder.decode(p09StateDump)!.footswitchFs1Mask,
        0x0002,
      ); // FX1 (bit 1)
      expect(
        decoder.decode(p05StateDump)!.footswitchFs1Mask,
        0x0040,
      ); // FX2 (bit 6)
      expect(
        decoder.decode(p05StateDump)!.footswitchFs2Mask,
        0x0100,
      ); // RVB (bit 8)
    },
  );

  test('returns null on a too-short / marker-less dump', () {
    expect(decoder.decode('8080F0F7'), isNull);
  });

  test('returns null on a long-but-non-hex dump (no throw)', () {
    final bad = '8080F0${'ZZ' * 300}F7';

    expect(decoder.decode(bad), isNull);
  });
}
