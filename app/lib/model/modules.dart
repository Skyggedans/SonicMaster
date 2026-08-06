/// Maps device module ids to short names (e.g. 3 -> "AMP").
class Modules {
  Modules(this.idToName)
    : _nameToId = {for (final e in idToName.entries) e.value: e.key};

  final Map<int, String> idToName;
  final Map<String, int> _nameToId;

  factory Modules.fromJson(Map<String, dynamic> json) => Modules({
    for (final e in json.entries) int.parse(e.key): e.value as String,
  });

  String? nameOf(int id) => idToName[id];
  int? idOf(String name) => _nameToId[name];
}
