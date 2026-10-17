import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/character_map.dart';
import 'package:sonicmaster/protocol/preset_name_codec.dart';

void main() {
  final characters = CharacterMap.fromJson(
    jsonDecode(File('assets/data/character_map.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  final codec = PresetNameCodec(characters);

  test('encodeForSave pads to 10 chars (40 hex) with 0000', () {
    final hex = codec.encodeForSave('AB');

    expect(hex.length, 40);
    // 'A' -> 0401, 'B' -> 0402, then eight padding 0000
    expect(hex.startsWith('04010402'), isTrue);
    expect(hex.endsWith('0000000000000000'), isTrue);
  });

  test('empty name is all padding', () {
    final hex = codec.encodeForSave('');

    expect(hex, '0' * 40);
  });

  test(
    'unknown char (not in map) encodes as padding, mapped chars around it',
    () {
      // 'A' is in the map (0401); '€' (euro sign) is not -> its slot is 0000.
      final hex = codec.encodeForSave('A€B');

      expect(hex.substring(0, 4), '0401'); // A
      expect(hex.substring(4, 8), '0000'); // unmapped -> padding
      expect(hex.substring(8, 12), '0402'); // B still encodes after the gap
    },
  );

  test('encode then decode round-trips a name (case-sensitive)', () {
    const name = 'Lead1';

    expect(codec.decode(codec.encodeForSave(name)), name);
  });

  test('decode upper-cases codes before lookup', () {
    // lowercase hex code for 'z' (070A) must still decode
    expect(codec.decode('070a'), 'z');
  });
}
