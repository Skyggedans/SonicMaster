import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/effect_library.dart';
import 'package:sonicmaster/model/effect_signatures.dart';
import 'package:sonicmaster/protocol/selected_effects_decoder.dart';
import '../fixtures/preset_state_dumps.dart';

void main() {
  final effects = EffectLibrary.fromJson(
    jsonDecode(File('assets/data/effect_library.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  final sig = EffectSignatures.build(
    jsonDecode(File('assets/data/effect_signatures.json').readAsStringSync())
        as Map<String, dynamic>,
    effects,
  );

  final decoder = SelectedEffectsDecoder(sig);

  test('decodes U01 selected effects (real capture)', () {
    expect(decoder.decode(u01StateDump), {
      0: 1, // NR: fixed single-effect module (Gate), no signature to decode
      1: 101,
      2: 201,
      3: 325, // AMP = Calif IIC+ (recovered in the preset sweep)
      4: 410,
      5: 501,
      6: 101,
      7: 705,
      8: 806,
      9: 901,
    });
  });

  test('decodes U02 selected effects (differs: IR/EQ/DLY)', () {
    expect(decoder.decode(u02StateDump), {
      0: 1, // NR: fixed single-effect module (Gate), no signature to decode
      1: 101,
      2: 201,
      3: 326, // AMP = Supero 2 OD (recovered in the preset sweep)
      4: 405,
      5: 502,
      6: 101,
      7: 702,
      8: 806,
      9: 901,
    });
  });

  test('always includes NR (module 0 -> fixed Gate fxId 1)', () {
    // NR has no signature/effect-variants, but always runs the Gate effect;
    // the editor/chain resolve it through this fixed mapping.
    expect(decoder.decode(u01StateDump)[0], 1);
  });

  test('decodes P12 legacy effects recovered off the pedal', () {
    // Fullchor/Flash/Doctor CL signatures were missing from the extracted data
    // (and the reference web app) until read off the device — regression guard.
    final decoded = decoder.decode(p12StateDump);

    expect(decoded[1], 119, reason: 'FX1 = Fullchor');
    expect(decoded[7], 710, reason: 'DLY = Flash');
    expect(decoded[3], 323, reason: 'AMP = Doctor CL');
    // and it still resolves the ordinary modules
    expect(decoded[2], 205, reason: 'DRV = Dark Mouse');
    expect(decoded[8], 807, reason: 'RVB = Spring');
  });

  test('decodes P05 legacy effects recovered off the pedal', () {
    final d = decoder.decode(p05StateDump);

    expect(d[3], 324, reason: 'AMP = Flyman B1');
    expect(d[6], 120, reason: 'FX2 = Phaser ST');
    expect(d[7], 711, reason: 'DLY = Damage');
  });

  test('decodes P09 effects from the preset-sweep batch', () {
    final d = decoder.decode(p09StateDump);

    expect(d[1], 121, reason: 'FX1 = Crystal Chorus');
    expect(d[3], 329, reason: 'AMP = Superb CL');
    expect(d[7], 715, reason: 'DLY = Shiny');
  });

  test('malformed dump -> empty (no NR seed for an undecodable dump)', () {
    expect(decoder.decode('8080F0F7'), isEmpty);
  });
}
