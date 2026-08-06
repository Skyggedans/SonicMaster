import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/effect_library.dart';
import 'package:sonicmaster/model/parameter_tables.dart';
import 'package:sonicmaster/protocol/parameter_values_decoder.dart';
import '../fixtures/preset_state_dumps.dart';

void main() {
  Map<String, dynamic> read(String f) =>
      jsonDecode(File('assets/data/$f.json').readAsStringSync())
          as Map<String, dynamic>;

  final effects = EffectLibrary.fromJson(read('effect_library'));
  final tables = ParameterTables.fromJson(
    read('algid_location_map'),
    read('value_reverse_lookup'),
  );

  final decoder = ParameterValuesDecoder(tables);

  const selU01 = {
    1: 101,
    2: 201,
    4: 410,
    5: 501,
    6: 101,
    7: 705,
    8: 806,
    9: 901,
  };

  test('decodes U01 parameter values (real capture)', () {
    final p = decoder.decode(u01StateDump, selU01, effects);

    expect(p[0], {0: 20}); // NR THRE (force-added)
    expect(p[2], {0: 0, 1: 75, 2: 50}); // DRV Scream
    expect(p[5], {
      0: -3,
      1: -12,
      2: -8,
      3: 0,
      4: 8,
      5: 50,
    }); // EQ bands (bipolar)
    // DLY Tube: Mix/Time/F.Back, plus the Sync (3) and Trail (4) toggles the
    // desktop capture never recorded — both off here, and this real dump is
    // independent evidence the pedal carries those two slots.
    expect(p[7], {0: 12, 1: 400, 2: 30, 3: 0, 4: 0});
    expect(p[8], {0: 25, 2: 50, 4: 50}); // RVB (packet 4)
    expect(p[9], {0: 50, 1: 50, 2: 50, 3: 50, 4: 50}); // Clone (packet 4)
  });

  test('value lookup preserves fractional values', () {
    // A modulation "Rate" (Hz) value is fractional; confirm it survives as num.
    expect(tables.valueLookup['0C0C0C0C030D'], 0.1);
  });

  test('decodes U02 (differs from U01)', () {
    const selU02 = {
      1: 101,
      2: 201,
      4: 405,
      5: 502,
      6: 101,
      7: 702,
      8: 806,
      9: 901,
    };

    final p = decoder.decode(u02StateDump, selU02, effects);

    expect(p[0], {0: 10}); // NR THRE differs
    expect(p[2], {0: 10, 1: 70, 2: 40}); // DRV differs
  });

  test('short dump -> empty', () {
    expect(decoder.decode('8080F0F7', selU01, effects), isEmpty);
  });
}
