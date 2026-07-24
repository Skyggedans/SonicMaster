import 'sysex_write_frame.dart';

/// Builds a preset-field write frame (`0402` family): payload
/// `11 42 [field] 20 01 00 [lo] [hi]`, the value 16-bit little-endian. Field
/// 01 = Patch Vol, 02 = BPM.
///
/// Patch Vol has captured frames in `command_library.json`; BPM does not (the
/// desktop tool never exposed it), so its frames must be synthesized. This
/// mirrors the captured Patch Vol framing exactly — verified byte-for-byte
/// against the captured table in tests — differing only in the high value byte,
/// which Patch Vol (0–100) can omit but BPM (40–260) needs.
class PresetFieldFrame {
  const PresetFieldFrame._();

  /// Field index for the preset volume slot.
  static const int volumeField = 1;

  /// Field index for the preset BPM slot.
  static const int bpmField = 2;

  /// Returns the full `8080…F7` frame hex for writing [value] to [field].
  static String build({required int field, required int value}) {
    // The 8-byte `0402`-family payload; the shared framing adds the tt=01/ss=00
    // header + CRC. The value is 16-bit little-endian.
    final payload = <int>[
      0x11,
      0x42,
      field,
      0x20,
      0x01,
      0x00,
      value & 0xFF,
      (value >> 8) & 0xFF,
    ];

    return buildSysexWriteFrame(payload);
  }
}
