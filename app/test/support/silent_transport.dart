import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/transport.dart';

/// A pedal that is connected but never answers: connect and disconnect succeed
/// at once, every frame is recorded in [sentFrames], and no packet ever
/// arrives.
///
/// The packet stream stays open for good. A closed stream (`Stream.empty()`)
/// ends DeviceService.inbound at once, so every later ACK wait would return
/// through its onDone instead of its timeout. With this transport an ACK wait
/// stays in flight until its 800 ms timeout; [pumpPastAckTimeout] then runs it
/// out.
class SilentTransport implements Transport {
  final _packets = StreamController<Uint8List>.broadcast();

  /// The frame hex of every [sendFrame] call, in order.
  final sentFrames = <String>[];

  @override
  Stream<Uint8List> rawPackets() => _packets.stream;

  @override
  Future<void> connect({String? target}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendFrame(String frameHex) async {
    sentFrames.add(frameHex);
  }

  @override
  Stream<bool>? connectionEvents() => null;
}

/// Runs out an ACK wait against a [SilentTransport]: pumps past its 800 ms
/// timeout (900 ms of fake time in all), with one real event-loop turn in
/// between. Call it before a test that started a preset load (or any other
/// ACK wait) ends: a pending ACK timer fails the test.
///
/// The real turn is required. awaitFirst (ack_waiter.dart) ends by awaiting
/// `StreamSubscription.cancel()`, whose future completes in the root zone, and
/// fake async never runs root-zone microtasks. Without the turn the wait stays
/// suspended after its timer fired, and the load never finishes.
Future<void> pumpPastAckTimeout(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 800));
  await tester.runAsync(() async {});
  await tester.pump(const Duration(milliseconds: 100));
}
