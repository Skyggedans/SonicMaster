/// Buffers and reassembles multi-packet USB SysEx responses.
/// Port of the reassembly path in the legacy `handleMidiMessage`.
class MultiPacketReassembler {
  final Map<String, _Response> _responses = {};

  /// Feeds one F0-started SysEx packet. Returns the reassembled `8080F0…F7`
  /// frame hex once the response is complete, otherwise null.
  String? addPacket(List<int> sysexBytes) {
    final total = (sysexBytes[3] << 4) | sysexBytes[4];
    final current = (sysexBytes[5] << 4) | sysexBytes[6];

    if (total <= 1) {
      // Single packet: legacy `handleMidiMessage` prepends 8080 to the raw
      // message verbatim (no reconstruction). Pass it through unchanged so
      // non-canonical reserved bytes / total==0 frames aren't corrupted.
      return _prefixed(sysexBytes);
    }

    final id = '${sysexBytes[3]}_${sysexBytes[4]}';
    final response = _responses.putIfAbsent(id, () => _Response());
    response.packets[current] = sysexBytes;

    final isComplete = Iterable<int>.generate(
      total,
    ).every((i) => response.packets.containsKey(i));

    if (!isComplete) return null;

    final payload = Iterable<int>.generate(
      total,
    ).expand((i) => _payloadOf(response.packets[i]!)).toList();

    _responses.remove(id);

    final first = response.packets[0]!;

    return _frameHex(first[1], first[2], payload);
  }

  static List<int> _payloadOf(List<int> pkt) => pkt.sublist(9, pkt.length - 1);

  static String _hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  /// Single-packet passthrough: `8080` prepended to the raw message, verbatim.
  static String _prefixed(List<int> bytes) => _hex([0x80, 0x80, ...bytes]);

  /// Synthetic single-packet frame for a completed multi-packet response
  /// (matches legacy's reconstructed `singlePacketMessage`).
  static String _frameHex(int mfr1, int mfr2, List<int> payload) => _hex(<int>[
    0x80,
    0x80,
    0xF0,
    mfr1,
    mfr2,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    ...payload,
    0xF7,
  ]);
}

class _Response {
  final Map<int, List<int>> packets = {};
}
