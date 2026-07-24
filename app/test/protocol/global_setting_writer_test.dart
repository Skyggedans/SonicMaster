import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/global_setting_writer.dart';

/// The writer must reproduce the real captured frames byte-for-byte. If any of
/// these fail, synthesis is wrong and we must NOT trust it on new addresses.
void main() {
  Matcher isFrame(String expected) => equals(expected.toLowerCase());

  group('dumpRecord reproduces captured level/volume globalCommands', () {
    test('inputLevel (a0=01,a1=03) across value + sign', () {
      expect(
        GlobalSettingWriter.dumpRecord(
          a0: 0x01,
          a1: 0x03,
          value: 0,
        ).toLowerCase(),
        isFrame(
          '8080f0020100010000000a0101010100010003000000000000000000000000f7',
        ),
      );
      expect(
        GlobalSettingWriter.dumpRecord(
          a0: 0x01,
          a1: 0x03,
          value: 20,
        ).toLowerCase(),
        isFrame(
          '8080f0010e00010000000a0101010100010003000000000104000000000000f7',
        ),
      );
      // −1 → int32-LE ff ff ff ff.
      expect(
        GlobalSettingWriter.dumpRecord(
          a0: 0x01,
          a1: 0x03,
          value: -1,
        ).toLowerCase(),
        isFrame(
          '8080f00f0f00010000000a0101010100010003000000000f0f0f0f0f0f0f0ff7',
        ),
      );
    });

    test('the other three levels + global volume (addresses differ)', () {
      expect(
        GlobalSettingWriter.dumpRecord(
          a0: 0x01,
          a1: 0x04,
          value: 0,
        ).toLowerCase(),
        isFrame(
          '8080f0030200010000000a0101010100010004000000000000000000000000f7',
        ),
      );
      expect(
        GlobalSettingWriter.dumpRecord(
          a0: 0x05,
          a1: 0x04,
          value: 0,
        ).toLowerCase(),
        isFrame(
          '8080f0070e00010000000a0101010100050004000000000000000000000000f7',
        ),
      );
      expect(
        GlobalSettingWriter.dumpRecord(
          a0: 0x02,
          a1: 0x04,
          value: 0,
        ).toLowerCase(),
        isFrame(
          '8080f0000700010000000a0101010100020004000000000000000000000000f7',
        ),
      );
      expect(
        GlobalSettingWriter.dumpRecord(
          a0: 0x02,
          a1: 0x02,
          value: 0,
        ).toLowerCase(),
        isFrame(
          '8080f00c0b00010000000a0101010100020002000000000000000000000000f7',
        ),
      );
      expect(
        GlobalSettingWriter.dumpRecord(
          a0: 0x02,
          a1: 0x02,
          value: 100,
        ).toLowerCase(),
        isFrame(
          '8080f00c0600010000000a0101010100020002000000000604000000000000f7',
        ),
      );
    });
  });

  group('standaloneBool reproduces the 0403 Mode/Re-amp frames', () {
    test('0403 off / on', () {
      expect(
        GlobalSettingWriter.standaloneBool(
          a: 0x04,
          b: 0x03,
          value: 0,
        ).toLowerCase(),
        isFrame('8080f0060c000100000006010104030000000000000000f7'),
      );
      expect(
        GlobalSettingWriter.standaloneBool(
          a: 0x04,
          b: 0x03,
          value: 1,
        ).toLowerCase(),
        isFrame('8080f0070a000100000006010104030001000000000000f7'),
      );
    });
  });

  // The real frames the Android app sent for each newly-bound setting (from the
  // 2026-07-24 labeled capture). Synthesizing them byte-exact proves the bound
  // addresses are correct.
  group('dumpRecord reproduces captured new-setting writes', () {
    void expectWrite(int a0, int a1, int value, String expected) {
      expect(
        GlobalSettingWriter.dumpRecord(
          a0: a0,
          a1: a1,
          value: value,
        ).toLowerCase(),
        isFrame(expected),
      );
    }

    test('Mode / Re-amp / EXP-FS Type / Backlight / ECO / Power / Batt', () {
      expectWrite(
        0x04,
        0x04,
        1,
        '8080f0070b00010000000a0101010100040004000000000001000000000000f7',
      ); // Mode=Wet
      expectWrite(
        0x06,
        0x04,
        1,
        '8080f0050d00010000000a0101010100060004000000000001000000000000f7',
      ); // Re-amp=On
      expectWrite(
        0x01,
        0x05,
        2,
        '8080f00c0100010000000a0101010100010005000000000002000000000000f7',
      ); // Type=DualFS
      expectWrite(
        0x03,
        0x02,
        10,
        '8080f0040400010000000a010101010003000200000000000a000000000000f7',
      ); // Backlight=10
      expectWrite(
        0x04,
        0x02,
        1,
        '8080f00b0700010000000a0101010100040002000000000001000000000000f7',
      ); // ECO=On
      expectWrite(
        0x05,
        0x02,
        1,
        '8080f00a0400010000000a0101010100050002000000000001000000000000f7',
      ); // Power Confirm=On
      expectWrite(
        0x06,
        0x02,
        1,
        '8080f0090100010000000a0101010100060002000000000001000000000000f7',
      ); // Batt Only=On
    });
  });

  group('registerWrite reproduces the captured EXP/FS Target frame', () {
    test('reg 0x17 sub 0x01 val 1', () {
      expect(
        GlobalSettingWriter.registerWrite(
          reg: 0x17,
          sub: 0x01,
          value: 1,
        ).toLowerCase(),
        isFrame('8080f008070001000000040101010700010001f7'),
      );
    });
  });

  group('action reproduces the captured Factory Reset frame', () {
    test('selector 0x3F', () {
      // Real reset write from the 2026-07-24 capture (BLE, 8080-prefixed here).
      expect(
        GlobalSettingWriter.action(selector: 0x3F).toLowerCase(),
        isFrame('8080f0040b0001000000020101030ff7'),
      );
    });
  });
}
