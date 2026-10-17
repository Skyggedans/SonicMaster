import 'crc8_smbus.dart';

/// Synthesizes device-global **write** frames for the pedal.
///
/// The whole thing is reverse-engineered and validated byte-for-byte against the
/// captured `globalCommands` frames (see `global_setting_writer_test.dart`), so we
/// no longer need a pre-captured frame per value — any address/value is buildable.
///
/// Wire shape: `8080 F0 <ck> <body…> F7`, where every logical byte is
/// **nibble-encoded** — split into two on-wire bytes, its high nibble then its low
/// nibble (`0x14 → 01 04`, `0xFF → 0f 0f`). The checksum `<ck>` is a single
/// **CRC-8/SMBUS** byte over the *logical* (de-nibbled) body, itself nibble-encoded.
///
/// Two families are used by the device, both handled here:
///  * [dumpRecord] — the family of every record in the `0100` settings dump
///    (input/FX-rec/BT-rec/monitor levels, global volume, Backlight, ECO, Power…):
///    selector `11 11`, then the record's first two address bytes, then a signed
///    32-bit little-endian value.
///  * [standaloneBool] — the standalone USB bools read via `020102 <A><B>` (Mode /
///    Re-amp at `0403`): selector `11 <(A<<4)|B>`, then a single value byte.
class GlobalSettingWriter {
  const GlobalSettingWriter._();

  /// Builds a "dump-record" write (selector `11 11`, signed int32-LE value).
  /// [a0]/[a1] are the record's first two address bytes as seen in the `0100`
  /// dump (e.g. inputLevel `01`/`03`, Backlight `08`/`04`); [value] is signed
  /// (dB levels run −20..20, enums/bools are their raw index).
  static String dumpRecord({
    required int a0,
    required int a1,
    required int value,
  }) => _frame([
    0x01, 0x00, 0x0A, 0x11, 0x11, //
    a0 & 0xFF, a1 & 0xFF, 0x00, 0x00,
    ..._int32le(value),
  ]);

  /// Builds a "standalone bool" write (selector `11 <(a<<4)|b>`, one value byte).
  /// [a]/[b] are the read-selector nibbles (`04`/`03` → `0x43`). Not observed in
  /// the wild for any current setting — kept for completeness.
  static String standaloneBool({
    required int a,
    required int b,
    required int value,
  }) => _frame([
    0x01, 0x00, 0x06, 0x11, ((a & 0x0F) << 4) | (b & 0x0F), //
    value & 0xFF, 0x00, 0x00, 0x00,
  ]);

  /// Builds a "register write" (`11 <reg> <sub> <val>`, one value byte). Used by
  /// EXP/FS Target: [reg] is `0x16` (footswitch) or `0x17` (expression), [sub] is
  /// the slot (EXP `01`; SingleFS `00`; DualFS FS1 `02` / FS2 `04`).
  static String registerWrite({
    required int reg,
    required int sub,
    required int value,
  }) => _frame([0x01, 0x00, 0x04, 0x11, reg & 0xFF, sub & 0xFF, value & 0xFF]);

  /// Builds a bare "action write" (`11 <selector>`, no value) — a fire-and-forget
  /// command. Used by Factory Reset (selector `0x3F`).
  static String action({required int selector}) =>
      _frame([0x01, 0x00, 0x02, 0x11, selector & 0xFF]);

  /// Wraps a logical body in `8080 F0 <ck> <body> F7`, computing the CRC and
  /// nibble-encoding both. Returns uppercase hex.
  static String _frame(List<int> logical) {
    final ck = Crc8Smbus.ofBytes(logical);

    final inner = _nibbleEncode([ck, ...logical]);

    return '8080F0${inner.toUpperCase()}F7';
  }

  /// Nibble-encodes each logical byte into two on-wire bytes (`b → 0{hi} 0{lo}`).
  static String _nibbleEncode(List<int> logical) {
    final sb = StringBuffer();

    for (final b in logical) {
      sb.write('0');
      sb.write(((b >> 4) & 0x0F).toRadixString(16));
      sb.write('0');
      sb.write((b & 0x0F).toRadixString(16));
    }

    return sb.toString();
  }

  /// Signed 32-bit little-endian encoding (−1 → `ff ff ff ff`, −20 → `ec ff ff ff`).
  static List<int> _int32le(int value) {
    final u = value & 0xFFFFFFFF;

    return [u & 0xFF, (u >> 8) & 0xFF, (u >> 16) & 0xFF, (u >> 24) & 0xFF];
  }
}
