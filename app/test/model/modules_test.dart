import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/modules.dart';

void main() {
  final json =
      jsonDecode(File('assets/data/modules.json').readAsStringSync())
          as Map<String, dynamic>;

  final modules = Modules.fromJson(json);

  test('maps known ids to names', () {
    expect(modules.nameOf(0), 'NR');
    expect(modules.nameOf(2), 'DRV');
    expect(modules.nameOf(3), 'AMP');
    expect(modules.nameOf(8), 'RVB');
  });

  test('reverse lookup by name', () {
    expect(modules.idOf('AMP'), 3);
    expect(modules.idOf('DLY'), 7);
  });

  test('unknown id/name returns null', () {
    expect(modules.nameOf(99), isNull);
    expect(modules.idOf('NOPE'), isNull);
  });
}
