import 'effect_library.dart';

/// Per-module effect signature layout + signature→fxId lookup, built from the
/// extracted `EFFECT_SIGNATURE_TO_NAME_MAP` and the effect library (name→id).
class ModuleSignatures {
  const ModuleSignatures(this.offset, this.length, this.signatureToFxId);

  final int offset;
  final int length;
  final Map<String, int> signatureToFxId; // UPPERCASE sig hex -> fxId
}

class EffectSignatures {
  const EffectSignatures(this.byModule);

  final Map<int, ModuleSignatures> byModule;

  factory EffectSignatures.build(
    Map<String, dynamic> sigJson,
    EffectLibrary effects,
  ) {
    final nameToId = <String, int>{
      for (final e in effects.effects.values) e.name: e.id,
    };

    final byModule = <int, ModuleSignatures>{};

    sigJson.forEach((moduleIdStr, spec) {
      final s = spec as Map<String, dynamic>;
      final sigs = s['signatures'] as Map<String, dynamic>;
      final map = <String, int>{};

      sigs.forEach((sigHex, name) {
        final id = nameToId[name as String];

        if (id != null) map[sigHex.toUpperCase()] = id;
      });

      byModule[int.parse(moduleIdStr)] = ModuleSignatures(
        s['offset'] as int,
        s['length'] as int,
        map,
      );
    });

    return EffectSignatures(byModule);
  }
}
