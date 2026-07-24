import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/global_settings_decoder.dart';

void main() {
  const decoder = GlobalSettingsDecoder();

  // Real capture from the device: globalVolume 60, all levels 0.
  const golden =
      '8080F0030F0001000000000102010000010001000400000006000000010001000200010004000000010000000000000002000200040000030C0000000000000001000200010000000000030002000100000005000100030001000000000001000400010000000000020004000100000000000300040001000000010004000400010000000100050004000100000000000600040001000000000004000200010000000000010005000100000000000800040006000000020000000C0000000D00000009000400020000000000000005000200010000000100060002000100000000F7';

  test('decodes the golden dump', () {
    final g = decoder.decode(golden);

    expect(g, isNotNull);
    expect(g!.globalVolume, 60);
    expect(g.inputLevel, 0);
    expect(g.fxRecLevel, 0);
    expect(g.monitorLevel, 0);
    expect(g.btRecLevel, 0);
  });

  // Builds a dumpHex whose payload has [value4hex] at [charOffset].
  String dumpWith(Map<int, String> at) {
    final buf = List.filled(400, '0');

    for (final MapEntry(key: off, value: v) in at.entries) {
      for (final (i, ch) in v.split('').indexed) {
        buf[off + i] = ch;
      }
    }

    return '0123456789${buf.join()}F7'; // 10-char prefix + payload + 'F7'
  }

  test('decodes global volume (b1*16 + b2) at 100', () {
    // 100 -> b1=06,b2=04 -> 100
    expect(decoder.decode(dumpWith({100: '0604'}))!.globalVolume, 100);
  });

  test('decodes dB levels via decodeDbValue', () {
    // inputLevel@172, fxRec@192, monitor@212, btRec@272
    final g = decoder.decode(
      dumpWith({172: '0F0F', 192: '0E0C', 212: '0104', 272: '0005'}),
    )!;

    expect(g.inputLevel, -1); // 0F,0F -> 15-16
    expect(g.fxRecLevel, -20); // 0E,0C -> 12-32
    expect(g.monitorLevel, 20); // 01,04 -> 16+4
    expect(g.btRecLevel, 5); // 00,05 -> 5
  });

  test('decodes the newly-bound Mode…EXP-FS-Type offsets', () {
    // Backlight@152, Mode@252, Re-amp@292, ECO@312, EXP/FS Type@332.
    final g = decoder.decode(
      dumpWith({
        152: '000A',
        252: '0001',
        292: '0001',
        312: '0001',
        332: '0002',
      }),
    )!;

    expect(g.backlight, 10); // 00,0A -> 10 (two-nibble)
    expect(g.mode, 1); // Wet
    expect(g.reamp, 1); // On
    expect(g.eco, 1); // On
    expect(g.expFsType, 2); // DualFS
  });

  test('a short dump (no ECO/EXP-Type records) decodes core, no crash', () {
    // Payload length 290: btRec@272 present, but ECO@312 / EXP-Type@332 run off
    // the end. _uAt must default those instead of throwing (which would return
    // null and lose the levels too).
    final short = '0123456789${'0' * 272}0005${'0' * 14}F7';

    final g = decoder.decode(short);

    expect(g, isNotNull);
    expect(g!.btRecLevel, 5); // core still decodes
    expect(g.eco, 0); // @312 past end -> default 0
    expect(g.expFsType, 0); // @332 past end -> default 0
  });

  test('returns null on a too-short dump', () {
    expect(decoder.decode('8080F00000F7'), isNull);
  });
}
