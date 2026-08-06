import 'sysex_write_frame.dart';

/// Builds a footswitch write frame (register `0x4D`): payload
/// `11 4D <switch> <module> <state>`, where `switch` is 0 for FS1 / 1 for FS2,
/// [moduleId] is the 0-based module, and `state` is 1 (on) / 0 (off).
///
/// This is a per-SWITCH toggle — the SAME layout the pedal uses for its `12 4D`
/// report — NOT a full-state write. So a radio None/FS1/FS2 change is two of
/// these (turn the target switch on, turn the previous one off); see
/// `setModuleFootswitch`. Verified byte-for-byte against captured device writes.
class FootswitchFrame {
  const FootswitchFrame._();

  /// Frame that sets [moduleId]'s membership on one switch (FS2 iff [isFs2]) to
  /// [isOn].
  static String build({
    required int moduleId,
    required bool isFs2,
    required bool isOn,
  }) =>
      buildSysexWriteFrame([0x11, 0x4D, isFs2 ? 1 : 0, moduleId, isOn ? 1 : 0]);
}
