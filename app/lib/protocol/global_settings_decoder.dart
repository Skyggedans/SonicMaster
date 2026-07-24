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

  /// Unsigned nibble-combined byte at [off] (`b1*16 + b2`).
  static int _u(String p, int off) =>
      int.parse(p.substring(off, off + 2), radix: 16) * 16 +
      int.parse(p.substring(off + 2, off + 4), radix: 16);

  /// Like [_u] but yields 0 when [off] runs past a short dump, so the core levels
  /// still decode even if the Mode…ECO records aren't present.
  static int _uAt(String p, int off) => off + 4 <= p.length ? _u(p, off) : 0;

  GlobalSettings? decode(String dumpHex) {
    try {
      if (dumpHex.length < 12) return null;

      final p = dumpHex.substring(10, dumpHex.length - 2);

      if (p.length < 276) return null;

      return GlobalSettings(
        globalVolume: _u(p, 100),
        inputLevel: _db(p, 172),
        fxRecLevel: _db(p, 192),
        monitorLevel: _db(p, 212),
        btRecLevel: _db(p, 272),
        // Bound from the 2026-07-24 labeled capture (char offsets into `p`).
        // Power Confirm (05,02) / Batt Only (06,02) are writable but absent from
        // this dump layout, so they stay at their optimistic value (not decoded).
        backlight: _uAt(p, 152),
        mode: _uAt(p, 252),
        reamp: _uAt(p, 292),
        eco: _uAt(p, 312),
        expFsType: _uAt(p, 332),
      );
    } catch (_) {
      return null;
    }
  }
}
