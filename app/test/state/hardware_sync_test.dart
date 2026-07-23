import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/command_library.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/protocol/inbound_message.dart';
import 'package:sonicmaster/state/hardware_sync.dart';
import '../fixtures/name_dumps.dart';
import '../fixtures/preset_state_dumps.dart';

void main() {
  HardwareSyncEvent? classify(String hex) =>
      classifyHardwareSync(InboundMessage.classify(hex));

  test('preset-notify decodes to the right User slot (real device bytes)', () {
    // index = hi*16 + lo. Frames captured live from footswitch stepping.
    expect(
      (classify('8080F00107000100000006010204030000000000000000F7')
              as PresetSelected)
          .preset,
      const PresetRef(PresetBank.user, 1),
    ); // 00 00 = index 0
    expect(
      (classify('8080F00001000100000006010204030001000000000000F7')
              as PresetSelected)
          .preset,
      const PresetRef(PresetBank.user, 2),
    ); // 00 01 = index 1
  });

  test('factory-range index maps to Factory bank', () {
    // 03 02 = index 50 = first Factory slot; 06 03 = index 99 = last.
    expect(
      (classify('8080F00902000100000006010204030302000000000000F7')
              as PresetSelected)
          .preset,
      const PresetRef(PresetBank.factory, 1),
    );
    expect(
      (classify('8080F00708000100000006010204030603000000000000F7')
              as PresetSelected)
          .preset,
      const PresetRef(PresetBank.factory, 50),
    );
  });

  test('state dump -> StateDump carrying the frame', () {
    final e = classify(u01StateDump);

    expect(e, isA<StateDump>());
    expect((e as StateDump).frameHex, u01StateDump);
  });

  test('other dumps and non-preset frames -> null', () {
    expect(classify(presetNamesDump), isNull); // names dump (01020400)
    expect(classify(cloneNamesDump), isNull); // clone names (01020204)
    // 020405 notify classifies as PresetSavedMessage (not a DataFrame) -> null
    expect(classify('8080F0070D000100000003010204050000F7'), isNull);
    // 010b notify is a DataFrame but 02010B at [24:30] -> null
    expect(
      classify('8080F00E020001000000060102010B0001000000000000F7'),
      isNull,
    );
  });

  group('12 4D footswitch toggle report (on-pedal change)', () {
    // Real device frames + the user's own labels: <switch 0=FS1/1=FS2> <module>
    // <state 1=on>. Values are single bytes in expanded nibble form (`00 0V`).
    test('"включение FS1" — NR onto FS1', () {
      final e =
          classify('8080F0000A0001000000050102040D000000000001F7')
              as FootswitchChanged;

      expect(e.module, 0);
      expect(e.isFs2, isFalse);
      expect(e.isOn, isTrue);
    });

    test('"выключение FS2" — NR off FS2', () {
      final e =
          classify('8080F006060001000000050102040D000100000000F7')
              as FootswitchChanged;

      expect(e.module, 0);
      expect(e.isFs2, isTrue);
      expect(e.isOn, isFalse);
    });

    test('higher module id in the middle byte (DLY=7 onto FS1)', () {
      final e =
          classify('8080F000000001000000050102040D000000070001F7')
              as FootswitchChanged;

      expect(e.module, 7);
      expect(e.isFs2, isFalse);
      expect(e.isOn, isTrue);
    });
  });
}
