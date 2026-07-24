import '../model/character_map.dart';

/// Encodes/decodes preset names to/from the device's 4-hex-per-character
/// encoding. Port of the legacy `encodeNameForSave` (+ its inverse).
class PresetNameCodec {
  const PresetNameCodec(this.characters);

  final CharacterMap characters;

  static const String _padding = '0000';
  static const int _nameLength = 10;

  /// Exactly [_nameLength] characters -> 40 hex chars. Characters beyond the
  /// name length, or any character not in the map, encode as padding.
  String encodeForSave(String name) {
    return List.generate(_nameLength, (i) {
      if (i >= name.length) return _padding;

      return characters.codeFor(name[i]) ?? _padding;
    }).join();
  }

  /// Splits [codesHex] into 4-hex codes, upper-cases each, and maps to
  /// characters, stopping at the first padding/unknown code.
  String decode(String codesHex) {
    final out = StringBuffer();

    for (var i = 0; i + 4 <= codesHex.length; i += 4) {
      final code = codesHex.substring(i, i + 4).toUpperCase();

      if (code == _padding) break;

      final ch = characters.charFor(code);

      if (ch == null) break;

      out.write(ch);
    }

    return out.toString();
  }
}
