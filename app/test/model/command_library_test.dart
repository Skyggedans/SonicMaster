import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/command_library.dart';

void main() {
  final json =
      jsonDecode(File('assets/data/command_library.json').readAsStringSync())
          as Map<String, dynamic>;

  final cmd = CommandLibrary.fromJson(json);

  test('module on/off commands are full sysex frames', () {
    final on = cmd.moduleOn(0)!;

    expect(on.startsWith('8080f0'), isTrue);
    expect(on.endsWith('f7'), isTrue);
    expect(cmd.moduleOff(0)!.endsWith('f7'), isTrue);
  });

  test('amp modes present', () {
    expect(cmd.ampFactory.startsWith('8080f0'), isTrue);
    expect(cmd.ampClone.startsWith('8080f0'), isTrue);
  });

  test('effect type lookup returns pre-baked hex', () {
    final hex = cmd.effectType(1, 101)!;

    expect(hex.startsWith('8080f0'), isTrue);
    expect(hex.endsWith('f7'), isTrue);
    expect(cmd.effectType(1, 999999), isNull);
  });

  test('effectIdsFor lists a module\'s available effects', () {
    final ids = cmd.effectIdsFor(1);

    expect(ids, contains(101));
    expect(ids, isNot(contains(201)));
  });

  test(
    'parameter command lookup (integer, negative, and decimal value keys)',
    () {
      final hex = cmd.parameterCommand(0, 0, '0')!;

      expect(hex.toLowerCase().startsWith('8080f0'), isTrue);
      expect(hex.toLowerCase().endsWith('f7'), isTrue);
      expect(cmd.parameterCommand(0, 0, '100'), isNotNull); // integer key
      expect(cmd.parameterCommand(1, 0, '0.1'), isNotNull); // decimal key (Hz)
      expect(
        cmd.parameterCommand(5, 0, '-50'),
        isNotNull,
      ); // negative key (EQ band)
      expect(cmd.parameterCommand(99, 99, '99'), isNull);
      expect(
        cmd.parameterCommand(0, 0, '0.5'),
        isNull,
      ); // no decimal key for an int param
    },
  );

  test('global command lookup (volume 0-100, levels bipolar -20..20)', () {
    expect(cmd.globalCommand('globalVolume', 0), isNotNull);
    expect(cmd.globalCommand('globalVolume', 100), isNotNull);
    expect(cmd.globalCommand('inputLevel', 20), isNotNull); // max
    expect(cmd.globalCommand('inputLevel', -20), isNotNull); // min (bipolar dB)
    expect(cmd.globalCommand('inputLevel', 40), isNull); // out of range
    expect(cmd.globalCommand('nope', 0), isNull);
  });

  test('preset select builds P##/F## keys', () {
    expect(cmd.presetSelect(.user, 1), isNotNull);
    expect(cmd.presetSelect(.user, 50), isNotNull);
    expect(cmd.presetSelect(.factory, 1), isNotNull);
    expect(cmd.presetSelect(.user, 51), isNull);
  });

  test('chain order command lookup (default order key)', () {
    const key = 'NR-FX1-FX2-DLY-RVB-DRV-AMP-IR-EQ';

    expect(cmd.chainOrderCommand(key), isNotNull);
    expect(cmd.chainOrderCommand('bogus-order'), isNull);
  });
}
