import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/ack_waiter.dart';
import 'package:sonicmaster/protocol/inbound_message.dart';

void main() {
  test('resolves true when an AckMessage arrives after send', () async {
    final controller = StreamController<InboundMessage>.broadcast();
    var sent = false;
    final ok = await awaitAck(controller.stream, () async {
      sent = true;
      controller.add(const AckMessage());
    });

    expect(sent, isTrue);
    expect(ok, isTrue);
    await controller.close();
  });

  test('resolves false on timeout when no ack arrives', () async {
    final controller = StreamController<InboundMessage>.broadcast();
    final ok = await awaitAck(
      controller.stream,
      () async {},
      timeout: const Duration(milliseconds: 50),
    );

    expect(ok, isFalse);
    await controller.close();
  });

  test('ignores non-ack messages', () async {
    final controller = StreamController<InboundMessage>.broadcast();
    final ok = await awaitAck(
      controller.stream,
      () async => controller.add(const DataFrame('8080F0AABBF7')),
      timeout: const Duration(milliseconds: 60),
    );

    expect(ok, isFalse);
    await controller.close();
  });

  test('resolves false when the stream closes before an ack', () async {
    final controller = StreamController<InboundMessage>.broadcast();
    final ok = await awaitAck(
      controller.stream,
      () async => controller.close(),
      timeout: const Duration(seconds: 5),
    );

    expect(ok, isFalse); // onDone -> false, not an uncaught StateError
    await controller.close();
  });

  test('propagates a send error (after cleaning up)', () async {
    final controller = StreamController<InboundMessage>.broadcast();

    await expectLater(
      awaitAck(
        controller.stream,
        () async => throw StateError('boom'),
        timeout: const Duration(seconds: 5),
      ),
      throwsA(isA<StateError>()),
    );
    await controller.close();
  });
}
