import '../model/effect_library.dart';
import '../model/parameter_tables.dart';

/// Decodes each selected effect's parameter values from a preset-state dump.
/// Port of the legacy `decodeParameterValues`, run over the 5 USB-split packets.
class ParameterValuesDecoder {
  const ParameterValuesDecoder(this.tables);

  final ParameterTables tables;

  static const _usbHeader = '8080F00706000100000000';

  Map<int, Map<int, num>> decode(
    String dumpHex,
    Map<int, int> selectedEffects,
    EffectLibrary effects,
  ) {
    try {
      return _decode(dumpHex, selectedEffects, effects);
    } catch (_) {
      return const {}; // any malformed/short dump -> empty, never throws
    }
  }

  Map<int, Map<int, num>> _decode(
    String dumpHex,
    Map<int, int> selectedEffects,
    EffectLibrary effects,
  ) {
    if (dumpHex.length < 1623) return const {};

    // The 5 USB-split packets (header + slice + F7), as byte-hex lists.
    final slices = [
      [22, 422],
      [422, 822],
      [822, 1222],
      [1222, 1622],
      [1622, dumpHex.length - 1],
    ];

    final packets = [
      for (final s in slices)
        _toBytes('$_usbHeader${dumpHex.substring(s[0], s[1])}F7'),
    ];

    final selected = {0: 1, ...selectedEffects}; // NR always fx slot 1
    final out = <int, Map<int, num>>{};

    selected.forEach((moduleId, fxId) {
      final def = effects.byId(fxId);

      if (def == null) return;

      final params = <int, num>{};

      for (final param in def.params) {
        final loc = tables.locations['${moduleId}_${param.algId}'];

        if (loc == null) continue;

        final packet = (loc.$1 >= 0 && loc.$1 < packets.length)
            ? packets[loc.$1]
            : null;

        // Value block is 6 bytes (12 hex chars), e.g. "000004080C02".
        if (packet == null || loc.$2 < 0 || packet.length < loc.$2 + 6) {
          continue;
        }

        final block = packet.sublist(loc.$2, loc.$2 + 6).join().toUpperCase();
        final value = tables.valueLookup[block];

        if (value != null) params[param.algId] = value;
      }

      if (params.isNotEmpty) out[moduleId] = params;
    });

    return out;
  }

  static List<String> _toBytes(String hex) => [
    for (var i = 0; i + 2 <= hex.length; i += 2) hex.substring(i, i + 2),
  ];
}
