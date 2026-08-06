import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/effect_library.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/state/names_providers.dart';

void main() {
  final effects = EffectLibrary.fromJson(
    jsonDecode(File('assets/data/effect_library.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  test('effectDisplayName prefers a user-name override', () {
    expect(effectDisplayName(901, effects, {901: 'My Clone'}), 'My Clone');
    // Falls back to the library name when no override.
    expect(effectDisplayName(901, effects, const {}), effects.byId(901)?.name);
    // Unknown id, no override -> '#id'.
    expect(effectDisplayName(99999, effects, const {}), '#99999');
  });

  test('presetChipLabel appends the name with a colon', () {
    const u5 = PresetRef(.user, 5);

    expect(presetChipLabel(u5, {u5: 'MyPatch'}), 'P05: MyPatch');
    expect(presetChipLabel(u5, const {}), 'P05');
    expect(presetChipLabel(u5, {u5: ''}), 'P05'); // empty name -> bare label
  });

  test('presetMatchesQuery matches label or name, case-insensitively', () {
    const u5 = PresetRef(.user, 5);
    final names = {u5: 'Clean Tone'};

    expect(presetMatchesQuery(u5, '', names), isTrue); // empty -> all
    expect(presetMatchesQuery(u5, 'clean', names), isTrue);
    expect(presetMatchesQuery(u5, 'P05', names), isTrue);
    expect(presetMatchesQuery(u5, 'metal', names), isFalse);
    expect(presetMatchesQuery(u5, '  ', names), isTrue); // blank -> all
  });
}
