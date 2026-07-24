/// A classified inbound SysEx frame from the device.
sealed class InboundMessage {
  const InboundMessage();

  static const String _ack = '8080F00B02000100000003010400080000F7';
  static const String _modified = '8080F0070A000100000003010204050001F7';
  static const String _saved = '8080F0070D000100000003010204050000F7';
  static const String _terminator = '8080F0030601050104000200000000F7';

  /// Classifies [hex] (any case) into a typed message.
  static InboundMessage classify(String hex) {
    final h = hex.toUpperCase();

    switch (h) {
      case _ack:
        return const AckMessage();
      case _modified:
        return const PresetModifiedMessage();
      case _saved:
        return const PresetSavedMessage();
      case _terminator:
        return const TerminatorMessage();
    }

    if (h.startsWith('8080F0') && h.endsWith('F7') && h.length >= 8) {
      return DataFrame(h);
    }

    return MalformedFrame(h);
  }
}

class AckMessage extends InboundMessage {
  const AckMessage();
}

class PresetModifiedMessage extends InboundMessage {
  const PresetModifiedMessage();
}

class PresetSavedMessage extends InboundMessage {
  const PresetSavedMessage();
}

class TerminatorMessage extends InboundMessage {
  const TerminatorMessage();
}

/// A well-formed frame that is not one of the known constants.
class DataFrame extends InboundMessage {
  const DataFrame(this.hex);
  final String hex;
}

/// A frame that lacks the expected SysEx framing.
class MalformedFrame extends InboundMessage {
  const MalformedFrame(this.hex);
  final String hex;
}
