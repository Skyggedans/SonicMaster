import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/character_map.dart';
import 'package:sonicmaster/protocol/crc8_smbus.dart';
import 'package:sonicmaster/protocol/hex_codec.dart';
import 'package:sonicmaster/protocol/preset_name_codec.dart';
import 'package:sonicmaster/protocol/save_preset_frame.dart';

void main() {
  final characters = CharacterMap.fromJson(
    jsonDecode(File('assets/data/character_map.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  final builder = SavePresetFrame(PresetNameCodec(characters));

  test('frame has header, terminator, and correct length', () {
    final frame = builder.build(name: 'Clean', presetNumber: 1);

    expect(frame.toLowerCase().startsWith('8080f0'), isTrue);
    expect(frame.toLowerCase().endsWith('f7'), isTrue);
  });

  test('embedded CRC is self-consistent with the payload', () {
    final frame = builder.build(name: 'Lead', presetNumber: 7);
    // strip header (6) + expanded CRC (4) ... terminator f7 (2)
    final withoutHeader = frame.substring(6); // drop 8080f0
    final expandedCrc = withoutHeader.substring(0, 4);
    final payload = withoutHeader.substring(4, withoutHeader.length - 2);
    final recomputed = HexCodec.expandByte(
      Crc8Smbus.ofHex(HexCodec.collapseNibbles(payload)),
    );

    expect(expandedCrc.toUpperCase(), recomputed.toUpperCase());
  });

  test('preset number encodes to nibble-expanded bytes', () {
    // presetNumber 1 -> value 0 -> "0000"; 50 -> value 49 (0x31) -> "0301"
    final f1 = builder.build(name: 'X', presetNumber: 1);

    expect(f1.toLowerCase().contains('0001000001030101040a0000'), isTrue);

    final f50 = builder.build(name: 'X', presetNumber: 50);

    expect(f50.toLowerCase().contains('0001000001030101040a0301'), isTrue);
  });

  test('rejects out-of-range preset numbers', () {
    expect(
      () => builder.build(name: 'X', presetNumber: 0),
      throwsArgumentError,
    );
    expect(
      () => builder.build(name: 'X', presetNumber: 51),
      throwsArgumentError,
    );
  });
}
