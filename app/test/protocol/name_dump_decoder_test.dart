import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/character_map.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/protocol/name_dump_decoder.dart';
import '../fixtures/name_dumps.dart';

void main() {
  final map = CharacterMap.fromJson(
    jsonDecode(File('assets/data/character_map.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  test('decodePresetNames returns 100 names mapped to the right slots', () {
    final names = decodePresetNames(presetNamesDump, map);

    expect(names.length, 100);
    expect(names[const PresetRef(.user, 1)], 'Smart Box');
    expect(names[const PresetRef(.user, 2)], 'Creamy OD');
    expect(names[const PresetRef(.user, 50)], 'PROBE'); // scratch slot
    expect(names[const PresetRef(.factory, 1)], 'Smart Box');
    expect(names[const PresetRef(.factory, 50)], 'Bass Q');
  });

  test('decodeUserNames (clone) returns 5 names', () {
    final n = decodeUserNames(
      cloneNamesDump,
      map,
      fallbackPrefix: 'User Profile',
    );
    expect(n, ['Empty', 'Empty', 'Empty', 'Empty', 'Empty']);
  });

  test('decodeUserNames (ir) returns 5 names', () {
    final n = decodeUserNames(irNamesDump, map, fallbackPrefix: 'User IR');
    expect(n, ['Pitch Blac', 'Koloss', 'None', 'Immutable', 'The Violen']);
  });

  test('stripNameFrame removes 8080F0 prefix and F7 suffix', () {
    expect(stripNameFrame('8080F0ABCDF7'), 'ABCD');
    expect(stripNameFrame('F0ABCDF7'), 'ABCD');
  });

  test(
    'isValidNameBlock: valid, trailing-padding, unknown-code, all-padding',
    () {
      // 'A' = 0401 then padding -> valid
      expect(isValidNameBlock('0401${'0000' * 9}', map), isTrue);
      // a real char AFTER padding starts -> invalid
      expect(isValidNameBlock('040100000401${'0000' * 7}', map), isFalse);
      // unknown code 0001 -> invalid
      expect(isValidNameBlock('0001${'0000' * 9}', map), isFalse);
      // all padding, no real char -> invalid
      expect(isValidNameBlock('0000' * 10, map), isFalse);
    },
  );

  test('decodeUserNames falls back for a short/blank frame', () {
    final n = decodeUserNames('8080F0F7', map, fallbackPrefix: 'User IR');
    expect(n, [
      'User IR 1',
      'User IR 2',
      'User IR 3',
      'User IR 4',
      'User IR 5',
    ]);
  });

  test('decodePresetNames omits a blank slot but keeps neighbor alignment', () {
    // Fixed layout: 20-byte header, then 20-byte name + 20-byte filler per slot.
    String block(String nameHex) => nameHex.padRight(40, '0');

    final filler = ''.padRight(40, '0');
    final payload =
        '${''.padRight(40, '0')}' // header
        '${block('0401')}$filler' // slot0 = 'A'
        '${block('0000')}$filler' // slot1 = blank -> omitted
        '${block('0402')}'; // slot2 = 'B'

    final names = decodePresetNames('8080F0${payload}F7', map);

    expect(names[const PresetRef(.user, 1)], 'A');
    expect(names.containsKey(const PresetRef(.user, 2)), isFalse);
    expect(names[const PresetRef(.user, 3)], 'B');
  });

  test('decoders are case-insensitive on the frame hex', () {
    expect(
      decodeUserNames(
        irNamesDump.toLowerCase(),
        map,
        fallbackPrefix: 'User IR',
      ),
      decodeUserNames(irNamesDump, map, fallbackPrefix: 'User IR'),
    );
  });
}
