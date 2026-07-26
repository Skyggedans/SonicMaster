/// Parameter-value decode tables: where each param's value block lives, and the
/// reverse map from a 6-byte value block to its decimal value.
class ParameterTables {
  const ParameterTables(this.locations, this.valueLookup);

  final Map<String, (int p, int o)>
  locations; // "moduleId_algId" -> packet/offset
  final Map<String, num> valueLookup; // UPPERCASE 12-hex block -> value

  factory ParameterTables.fromJson(
    Map<String, dynamic> loc,
    Map<String, dynamic> val,
  ) => ParameterTables(
    {
      for (final e in loc.entries)
        e.key: (
          (e.value as Map<String, dynamic>)['p'] as int,
          (e.value as Map<String, dynamic>)['o'] as int,
        ),
    },
    {for (final e in val.entries) e.key.toUpperCase(): e.value as num},
  );
}
