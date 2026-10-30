import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/footswitch_frame.dart';

void main() {
  // Golden frames captured off the vendor Android app's BLE-MIDI writes
  // (tools/re/btsnoop_midi.py). BLE strips the '8080' USB prefix, added back
  // here. Payload = 11 4D <switch 0=FS1/1=FS2> <module> <state 1=on> — a single
  // switch toggle (same layout as the pedal's 12 4D report).
  group('FootswitchFrame — byte-exact against captured device writes', () {
    test('NR (module 0)', () {
      expect(
        FootswitchFrame.build(moduleId: 0, isFs2: false, isOn: true),
        '8080f00a0c0001000000050101040d000000000001f7', // FS1 on
      );
      expect(
        FootswitchFrame.build(moduleId: 0, isFs2: false, isOn: false),
        '8080f00a0b0001000000050101040d000000000000f7', // FS1 off
      );
      expect(
        FootswitchFrame.build(moduleId: 0, isFs2: true, isOn: true),
        '8080f00c070001000000050101040d000100000001f7', // FS2 on
      );
      expect(
        FootswitchFrame.build(moduleId: 0, isFs2: true, isOn: false),
        '8080f00c000001000000050101040d000100000000f7', // FS2 off
      );
    });

    test('DLY (module 7): higher index in the module byte', () {
      expect(
        FootswitchFrame.build(moduleId: 7, isFs2: false, isOn: true),
        '8080f00c070001000000050101040d000000070001f7', // FS1 on
      );
      expect(
        FootswitchFrame.build(moduleId: 7, isFs2: true, isOn: true),
        '8080f00a0c0001000000050101040d000100070001f7', // FS2 on
      );
    });

    test('the state byte is last, the switch byte first', () {
      // FS2 on vs FS2 off for DLY differ only in the final (state) byte.
      expect(
        FootswitchFrame.build(
          moduleId: 7,
          isFs2: true,
          isOn: true,
        ).endsWith('070001f7'),
        isTrue,
      );
      expect(
        FootswitchFrame.build(
          moduleId: 7,
          isFs2: true,
          isOn: false,
        ).endsWith('070000f7'),
        isTrue,
      );
    });
  });
}
