import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/character_map.dart';

void main() {
  final json =
      jsonDecode(File('assets/data/character_map.json').readAsStringSync())
          as Map<String, dynamic>;

  final map = CharacterMap.fromJson(json);

  test('decodes known codes', () {
    expect(map.charFor('0300'), '0');
    expect(map.charFor('0401'), 'A');
    expect(map.charFor('0200'), ' ');
    expect(map.charFor('0000'), isNull); // padding
  });

  test('encodes chars back to codes', () {
    expect(map.codeFor('A'), '0401');
    expect(map.codeFor('z'), '070A');
  });
}
