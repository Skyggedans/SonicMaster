import '../model/character_map.dart';
import '../model/preset_ref.dart';

/// Hex chars in one name block: 10 char-codes × 2 bytes × 2 hex = 40.
const _nameHex = 40;

/// Strips the synthetic `8080F0…F7` framing from a reassembled DataFrame hex,
/// returning the upper-cased inner payload. Tolerates a bare `F0…F7`.
String stripNameFrame(String frameHex) {
  var h = frameHex.toUpperCase();

  if (h.startsWith('8080F0')) {
    h = h.substring(6);
  } else if (h.startsWith('F0')) {
    h = h.substring(2);
  }

  if (h.endsWith('F7')) h = h.substring(0, h.length - 2);

  return h;
}

/// True if [hex40] is a valid 10-code name block: every code is known, once a
/// `0000` padding code appears every later code is `0000`, and at least one
/// real (non-null) character is present. Ports the web app's `isValidNameBlock`.
bool isValidNameBlock(String hex40, CharacterMap map) {
  if (hex40.length != _nameHex) return false;

  var padding = false;
  var hasChar = false;

  for (var i = 0; i < 10; i++) {
    final code = hex40.substring(i * 4, i * 4 + 4).toUpperCase();

    if (padding) {
      if (code != '0000') return false;
    } else if (!map.codeToChar.containsKey(code)) {
      return false; // unknown code -> not a name block
    } else if (map.charFor(code) == null) {
      padding = true; // '0000' -> padding starts
    } else {
      hasChar = true;
    }
  }

  return hasChar;
}

/// Decodes one name block, stopping at the first padding/unknown code.
String _decodeBlock(String hex40, CharacterMap map) {
  final out = StringBuffer();

  for (var i = 0; i + 4 <= hex40.length; i += 4) {
    final ch = map.charFor(hex40.substring(i, i + 4).toUpperCase());

    if (ch == null) break; // padding ('0000') or unknown

    out.write(ch);
  }

  return out.toString();
}

/// Extracts [count] fixed-position name blocks from reassembled [frameHex]:
/// block i is 20 bytes at byte offset `headerBytes + strideBytes*i`. A slot
/// whose block is missing or not a valid name block yields ''. Fixed offsets
/// (not a sliding scan) keep slot alignment even for a blank slot — the pedal
/// lays these dumps out on a perfectly regular stride (verified live).
List<String> _decodeFixed(
  String frameHex,
  CharacterMap map, {
  required int headerBytes,
  required int strideBytes,
  required int count,
}) {
  final payload = stripNameFrame(frameHex);

  return List.generate(count, (i) {
    final start = (headerBytes + strideBytes * i) * 2;
    final end = start + _nameHex;

    if (end > payload.length) return '';

    final block = payload.substring(start, end);

    return isValidNameBlock(block, map) ? _decodeBlock(block, map) : '';
  });
}

/// Decodes the 100 preset names (`020400` dump) into a `PresetRef -> name` map
/// (User P01–P50 then Factory F01–F50). Slots with no valid name are omitted.
/// Layout: first block at byte 20, stride 40, 100 slots.
Map<PresetRef, String> decodePresetNames(String frameHex, CharacterMap map) {
  final names = _decodeFixed(
    frameHex,
    map,
    headerBytes: 20,
    strideBytes: 40,
    count: 100,
  );

  final refs = PresetRef.all();
  final out = <PresetRef, String>{};

  for (var i = 0; i < names.length && i < refs.length; i++) {
    if (names[i].isNotEmpty) out[refs[i]] = names[i];
  }

  return out;
}

/// Decodes the 5 User-Profile / User-IR names (`020204` / `020200` dump).
/// Layout: first block at byte 22, stride 32, 5 slots. Empty slots become
/// "`$fallbackPrefix N`". Always returns exactly 5 names.
List<String> decodeUserNames(
  String frameHex,
  CharacterMap map, {
  required String fallbackPrefix,
}) {
  final names = _decodeFixed(
    frameHex,
    map,
    headerBytes: 22,
    strideBytes: 32,
    count: 5,
  );

  return [
    for (final (i, name) in names.indexed)
      name.isNotEmpty ? name : '$fallbackPrefix ${i + 1}',
  ];
}
