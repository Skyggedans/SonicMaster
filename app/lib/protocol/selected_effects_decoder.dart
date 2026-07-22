import '../model/effect_signatures.dart';

/// Decodes which effect fxId is selected per module from a preset-state dump.
/// Port of the legacy `decodeSelectedEffects`, run on the second USB-split
/// packet. Unrecognized signatures are skipped (as in the legacy).
class SelectedEffectsDecoder {
  const SelectedEffectsDecoder(this.signatures);

  final EffectSignatures signatures;

  static const _usbHeader = '8080F00706000100000000';

  Map<int, int> decode(String dumpHex) {
    if (dumpHex.length < 822) return const {};

    final packet1 = '$_usbHeader${dumpHex.substring(422, 822)}F7';
    final bytes = [
      for (var i = 0; i + 2 <= packet1.length; i += 2)
        packet1.substring(i, i + 2),
    ];

    // NR is a fixed single-effect module: it always runs the Gate effect
    // (fxId 1) and so has no signature to decode (keys 1-9 only). Seed it here
    // — mirroring ParameterValuesDecoder's identical `{0: 1}` convention — so
    // the editor and chain resolve NR's effect instead of showing it as unset.
    final result = <int, int>{0: 1};

    signatures.byModule.forEach((moduleId, spec) {
      if (bytes.length < spec.offset + spec.length) return;

      final sig = bytes
          .sublist(spec.offset, spec.offset + spec.length)
          .join()
          .toUpperCase();

      final fxId = spec.signatureToFxId[sig];

      if (fxId != null) result[moduleId] = fxId;
    });

    return result;
  }
}
