import 'dart:async';

import '../protocol/inbound_message.dart';

/// Runs [send] and returns the first inbound message [select] maps to non-null
/// (arriving before [timeout]), or null on timeout / stream close.
///
/// Subscribes before sending so a fast reply is not missed, and always cancels
/// its subscription and timer — no leaked listeners on the broadcast stream. If
/// [send] throws, cleanup still runs and the error propagates to the caller.
Future<R?> awaitFirst<R>(
  Stream<InboundMessage> inbound,
  Future<void> Function() send,
  R? Function(InboundMessage) select, {
  Duration timeout = const Duration(milliseconds: 800),
}) async {
  final completer = Completer<R?>();

  void complete(R? value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  final sub = inbound.listen(
    (m) {
      final r = select(m);

      if (r != null) complete(r);
    },
    onError: (_) {},
    onDone: () => complete(null),
  );

  final timer = Timer(timeout, () => complete(null));

  // Fire the send concurrently rather than awaiting it first: a stalled native
  // write must not outlast [timeout] (otherwise it hangs here forever and, run
  // inside the serialized IO gate, poisons every later read for the session). A
  // send failure still surfaces — it completes the future with the error.
  unawaited(
    send().catchError((Object e, StackTrace st) {
      if (!completer.isCompleted) completer.completeError(e, st);
    }),
  );

  try {
    return await completer.future;
  } finally {
    timer.cancel();
    await sub.cancel();
  }
}

/// Runs [send], resolving `true` when an [AckMessage] arrives before [timeout].
Future<bool> awaitAck(
  Stream<InboundMessage> inbound,
  Future<void> Function() send, {
  Duration timeout = const Duration(milliseconds: 800),
}) async =>
    (await awaitFirst<bool>(
      inbound,
      send,
      (m) => m is AckMessage ? true : null,
      timeout: timeout,
    )) ??
    false;
