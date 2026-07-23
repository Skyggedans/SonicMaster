import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/preset_field_frame.dart';

void main() {
  // Golden frames computed by the reverse-engineering builder (tools/re), which
  // reproduces the captured Patch Vol frames byte-for-byte. Here they anchor the
  // Dart synthesis: CRC-8/SMBUS + nibble expansion must match exactly.
  group('PresetFieldFrame', () {
    test('Patch Vol (field 1)', () {
      expect(
        PresetFieldFrame.build(field: PresetFieldFrame.volumeField, value: 50),
        '8080f0080e00010000000801010402000102000001000003020000f7',
      );
      expect(
        PresetFieldFrame.build(field: PresetFieldFrame.volumeField, value: 100),
        '8080f00f0c00010000000801010402000102000001000006040000f7',
      );
    });

    test('Preset BPM (field 2) spans the full 40-260 range via the high byte', () {
      expect(
        PresetFieldFrame.build(field: PresetFieldFrame.bpmField, value: 40),
        '8080f0020000010000000801010402000202000001000002080000f7',
      );
      expect(
        PresetFieldFrame.build(field: PresetFieldFrame.bpmField, value: 120),
        '8080f0020c00010000000801010402000202000001000007080000f7',
      );
      // 260 = 0x0104: needs the high byte. A one-byte frame would truncate to 4.
      expect(
        PresetFieldFrame.build(field: PresetFieldFrame.bpmField, value: 260),
        '8080f0070500010000000801010402000202000001000000040001f7',
      );
    });

    test('value is little-endian: low byte then high byte', () {
      final f = PresetFieldFrame.build(
        field: PresetFieldFrame.bpmField,
        value: 260,
      );

      // …0000 0004 0001 F7  ->  low=0x04, high=0x01  (collapsed nibbles)
      expect(f.endsWith('000004000 1f7'.replaceAll(' ', '')), isTrue);
    });
  });
}
