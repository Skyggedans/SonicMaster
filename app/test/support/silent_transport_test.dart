import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/device_service.dart';

import 'silent_transport.dart';

void main() {
  testWidgets('an ACK wait stays in flight until its 800 ms timeout', (
    tester,
  ) async {
    final transport = SilentTransport();
    final service = DeviceService(transport)..startListening();

    addTearDown(service.dispose);

    bool? isAcked;

    unawaited(service.sendAndAwaitAck('F0F7').then((value) => isAcked = value));
    await tester.pump(const Duration(milliseconds: 799));
    // A real event-loop turn (see pumpPastAckTimeout): a closed packet stream
    // would end the wait right here.
    await tester.runAsync(() async {});
    await tester.pump();

    expect(transport.sentFrames, ['F0F7']);
    expect(isAcked, isNull);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(() async {});
    await tester.pump();

    expect(isAcked, isFalse);
  });

  testWidgets('every wait of a session times out on its own', (tester) async {
    final service = DeviceService(SilentTransport())..startListening();

    addTearDown(service.dispose);

    final results = <bool>[];

    unawaited(service.sendAndAwaitAck('F0F7').then(results.add));
    await pumpPastAckTimeout(tester);
    unawaited(service.sendAndAwaitAck('F0F7').then(results.add));
    await tester.pump(const Duration(milliseconds: 799));
    // A real event-loop turn (see pumpPastAckTimeout): a wait that ended early
    // would be in results by now.
    await tester.runAsync(() async {});

    expect(results, [false]);

    await pumpPastAckTimeout(tester);

    expect(results, [false, false]);
  });
}
