import 'crc8_smbus.dart';
import 'hex_codec.dart';
import 'preset_name_codec.dart';

/// Builds the `040A` save-preset SysEx frame. Port of the legacy
/// `saveCurrentPreset` framing (the one command not pre-baked in the library).
class SavePresetFrame {
  const SavePresetFrame(this.nameCodec);

  final PresetNameCodec nameCodec;

  static const String _header = '8080f0';
  static const String _terminator = 'f7';
  static const String _template =
      '0001000001030101040a{PRESET_BYTES}000000000000{ENCODED_NAME}000000000000';

  /// [presetNumber] is 1–50. Returns the full frame hex.
  String build({required String name, required int presetNumber}) {
    if (presetNumber < 1 || presetNumber > 50) {
      throw ArgumentError.value(
        presetNumber,
        'presetNumber',
        'must be between 1 and 50',
      );
    }

    final value = presetNumber - 1;
    final valueHex = value.toRadixString(16).padLeft(2, '0');
    final presetBytes = '0${valueHex[0]}0${valueHex[1]}';

    final payload = _template
        .replaceFirst('{PRESET_BYTES}', presetBytes)
        .replaceFirst('{ENCODED_NAME}', nameCodec.encodeForSave(name));

    final crc = Crc8Smbus.ofHex(HexCodec.collapseNibbles(payload));

    return '$_header${HexCodec.expandByte(crc)}$payload$_terminator';
  }
}
