import '../model/global_settings.dart';

/// Decodes the device-global settings dump (`020102 0100` reply). Offsets are
/// char indices into `payload = dumpHex[10 .. len-2]`. Returns null on a
/// malformed/short dump. Port of the legacy `decodeGlobalSettings`.
class GlobalSettingsDecoder {
  const GlobalSettingsDecoder();

  /// dB value: b1 0x0F -> b2-16, 0x0E -> b2-32, else b1*16 + b2.
  static int _db(String p, int off) {
    final b1 = int.parse(p.substring(off, off + 2), radix: 16);
    final b2 = int.parse(p.substring(off + 2, off + 4), radix: 16);

    if (b1 == 0x0F) return b2 - 16;

    if (b1 == 0x0E) return b2 - 32;

    return b1 * 16 + b2;
  }

  GlobalSettings? decode(String dumpHex) {
    try {
      if (dumpHex.length < 12) return null;

      final p = dumpHex.substring(10, dumpHex.length - 2);

      if (p.length < 276) return null;

      return GlobalSettings(
        globalVolume:
            int.parse(p.substring(100, 102), radix: 16) * 16 +
            int.parse(p.substring(102, 104), radix: 16),
        inputLevel: _db(p, 172),
        fxRecLevel: _db(p, 192),
        monitorLevel: _db(p, 212),
        btRecLevel: _db(p, 272),
      );
    } catch (_) {
      return null;
    }
  }
}
