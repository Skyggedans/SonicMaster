import 'dart:typed_data';

import '../protocol/inbound_message.dart';
import '../protocol/multi_packet_reassembler.dart';

/// Turns a stream of raw wire messages (each a complete `F0 … F7`) into a
/// stream of classified [InboundMessage]s, reassembling multi-packet responses
/// via a single [MultiPacketReassembler].
///
/// Hardened against noise: USB MIDI interleaves short System Real-Time bytes
/// (Active Sensing `0xFE`, Clock `0xF8`, …) and can deliver truncated packets.
/// Anything that isn't a plausible SysEx packet is skipped, and a packet that
/// still trips the reassembler is dropped — one bad message must never unwind
/// this generator and kill the whole session's inbound pipeline.
Stream<InboundMessage> classifyInbound(Stream<Uint8List> wireMessages) async* {
  final reassembler = MultiPacketReassembler();

  await for (final message in wireMessages) {
    // Reassembler indexes bytes[3..6]; a SysEx packet is F0-led and >= 7 bytes.
    if (message.length < 7 || message.first != 0xF0) continue;

    String? frameHex;

    try {
      frameHex = reassembler.addPacket(message);
    } catch (_) {
      continue;
    }

    if (frameHex != null) {
      yield InboundMessage.classify(frameHex);
    }
  }
}
