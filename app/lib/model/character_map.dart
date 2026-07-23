/// Device preset-name character encoding: 4-hex code <-> character.
class CharacterMap {
  CharacterMap(this.codeToChar)
    : _charToCode = {
        for (final e in codeToChar.entries)
          if (e.value != null) e.value!: e.key,
      };

  final Map<String, String?> codeToChar;
  final Map<String, String> _charToCode;

  String? charFor(String code) => codeToChar[code];
  String? codeFor(String char) => _charToCode[char];

  factory CharacterMap.fromJson(Map<String, dynamic> json) =>
      CharacterMap({for (final e in json.entries) e.key: e.value as String?});
}
