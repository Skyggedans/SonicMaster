import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/command_library.dart';
import '../model/effect_library.dart';
import '../model/preset_ref.dart';

/// Decoded preset names (`PresetRef -> name`), populated in the background by
/// `refreshNames`. Empty until first fetched; chips fall back to the slot label.
final presetNamesProvider = StateProvider<Map<PresetRef, String>>(
  (_) => const {},
);

/// Decoded User-Profile (fxId 901–905) and User-IR (416–420) names, overriding
/// the static effect-library names in dropdowns. Empty until first fetched.
final userNamesProvider = StateProvider<Map<int, String>>((_) => const {});

/// The preset-browser search query (matches slot label + decoded name).
final presetSearchProvider = StateProvider<String>((_) => '');

/// The active preset-browser bank tab (Factory or User); User by default.
final presetTabProvider = StateProvider<PresetBank>((_) => .user);

/// Display name for effect [id], preferring a live-decoded User-Profile/IR name
/// from [userNames] over the static library name; `'#id'` if unknown.
String effectDisplayName(
  int id,
  EffectLibrary effects,
  Map<int, String> userNames,
) => userNames[id] ?? effects.byId(id)?.name ?? '#$id';

/// Chip label for [ref]: "P05: MyPatch" when a name is known, else "P05".
String presetChipLabel(PresetRef ref, Map<PresetRef, String> names) {
  final name = names[ref];

  return (name == null || name.isEmpty) ? ref.label : '${ref.label}: $name';
}

/// True if [ref] matches search [query] (case-insensitive over label + name).
/// An empty/blank query matches everything.
bool presetMatchesQuery(
  PresetRef ref,
  String query,
  Map<PresetRef, String> names,
) {
  final q = query.trim().toLowerCase();

  if (q.isEmpty) return true;

  return '${ref.label} ${names[ref] ?? ''}'.toLowerCase().contains(q);
}
