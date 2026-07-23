import '../model/decoded_preset_state.dart';
import '../model/modules.dart';

/// Decodes a preset-state dump (`020401` reply, reassembled `8080…F7`) into
/// module states, chain order, amp mode, and preset volume. Port of the legacy
/// `decodePresetStateAndOrder`, run on the first of the USB 5-packet split.
class PresetStateDecoder {
  const PresetStateDecoder(this.modules);

  final Modules modules;

  static const _usbHeader = '8080F00706000100000000';
  // Per-preset fields share one layout: `<idx>020000040000` then a 16-bit
  // little-endian value (low byte, high byte). Index 01 = Patch Vol, 02 = BPM.
  static const _volumeMarker = '01020000040000';
  static const _bpmMarker = '02020000040000';
  static const _chainMarker = '0A000000';

  // Footswitch assignment lives in the dump tail as two 16-bit little-endian
  // bitmasks (bit M = module id M reacts to that switch). Each is 2 real bytes,
  // and every real byte is stored as two nibble-bytes (hi, lo) in the expanded
  // dump. The offsets are the `dumpHex` byte of each mask's first nibble =
  // MultiPacketReassembler's 11-byte header + blob 936 (FS1) / 944 (FS2).
  // Confirmed on device: NR→bit0, DLY→bit7, RVB→bit8.
  static const _fs1MaskByte = 947;
  static const _fs2MaskByte = 955;

  /// Reads the 16-bit LE value that follows [marker], or null if the marker is
  /// absent / lands off a byte boundary / runs past the payload. Patch Vol
  /// (0–100) fits the low byte alone, but BPM (40–260) needs both.
  static int? _readU16(List<String> payload, String payloadStr, String marker) {
    final mi = payloadStr.indexOf(marker);

    if (mi < 0 || mi.isOdd) return null;

    final b = (mi + marker.length) ~/ 2;

    if (b + 3 >= payload.length) return null;

    final lo =
        (int.parse(payload[b], radix: 16) << 4) |
        int.parse(payload[b + 1], radix: 16);
    final hi =
        (int.parse(payload[b + 2], radix: 16) << 4) |
        int.parse(payload[b + 3], radix: 16);

    return (hi << 8) | lo;
  }

  /// Reads a 16-bit little-endian footswitch bitmask whose first nibble-byte is
  /// at [byteOffset] in [dumpHex]: two real bytes, each two nibble-bytes (hi,
  /// lo). Returns 0 if the offset runs past the dump.
  int _footswitchMask(String dumpHex, int byteOffset) {
    if ((byteOffset + 4) * 2 > dumpHex.length) return 0;

    int nibbleByte(int b) =>
        int.tryParse(dumpHex.substring(b * 2, b * 2 + 2), radix: 16) ?? 0;

    final low = (nibbleByte(byteOffset) << 4) | nibbleByte(byteOffset + 1);
    final high = (nibbleByte(byteOffset + 2) << 4) | nibbleByte(byteOffset + 3);

    return low | (high << 8);
  }

  /// Returns null on any malformed/short dump (too short, missing chain marker,
  /// or non-hex bytes) rather than throwing.
  DecodedPresetState? decode(String dumpHex) {
    try {
      return _decode(dumpHex);
    } catch (_) {
      return null;
    }
  }

  DecodedPresetState? _decode(String dumpHex) {
    if (dumpHex.length < 422) return null;

    // First split packet: header + dump[22:422] + F7, then drop 5-byte head + F7.
    final packet0 = '$_usbHeader${dumpHex.substring(22, 422)}F7';
    final bytes = _toBytes(packet0);
    final payload = bytes.sublist(5, bytes.length - 1);
    final payloadStr = payload.join();

    final presetVolume = _readU16(payload, payloadStr, _volumeMarker) ?? 75;
    final presetBpm = _readU16(payload, payloadStr, _bpmMarker) ?? 120;

    final csi = payloadStr.lastIndexOf(_chainMarker);

    if (csi < 0) return null;

    final chainByteIndex = csi ~/ 2;
    final globalStateByteIndex = chainByteIndex - 10;
    final n1 = chainByteIndex - 13;
    final n2 = chainByteIndex - 12;

    if (globalStateByteIndex < 0 || n1 < 0) return null;

    final nibble1 = payload[n1];
    final nibble2 = payload[n2];
    final globalStateByte = int.parse(payload[globalStateByteIndex], radix: 16);
    final isCloneMode = (globalStateByte & 2) != 0;
    final rvbOn = (globalStateByte & 1) != 0;
    final mainBitmask = int.parse(nibble1[1] + nibble2[1], radix: 16);

    final moduleStates = <String, bool>{};

    for (var i = 0; i < 9; i++) {
      final name = modules.nameOf(i);

      if (name == null) continue;

      var isOn = (i == 8) ? rvbOn : (mainBitmask & (1 << i)) != 0;

      if (isCloneMode && i == 4) isOn = true;

      moduleStates[name] = isOn;
    }

    final chainDataStart = chainByteIndex + _chainMarker.length ~/ 2;
    final chainData = payload.sublist(chainDataStart);
    final chainIds = <int>[];
    final seen = <int>{};
    var nrFound = false;

    for (var i = 0; i < chainData.length - 1; i++) {
      if (chainIds.length >= 9) break;

      final id = int.parse(chainData[i], radix: 16);

      if (modules.nameOf(id) != null &&
          chainData[i + 1] == '00' &&
          !seen.contains(id)) {
        chainIds.add(id);
        seen.add(id);

        if (id == 0) nrFound = true;

        i++;
      }
    }

    if (!nrFound && chainIds.length < 9) chainIds.insert(0, 0);

    return DecodedPresetState(
      isCloneMode: isCloneMode,
      presetVolume: presetVolume,
      presetBpm: presetBpm,
      moduleStates: moduleStates,
      chainOrder: [for (final id in chainIds) modules.nameOf(id)!],
      footswitchFs1Mask: _footswitchMask(dumpHex, _fs1MaskByte),
      footswitchFs2Mask: _footswitchMask(dumpHex, _fs2MaskByte),
    );
  }

  static List<String> _toBytes(String hex) => [
    for (var i = 0; i + 2 <= hex.length; i += 2) hex.substring(i, i + 2),
  ];
}
