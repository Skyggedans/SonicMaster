import 'dart:async';

import '../protocol/inbound_message.dart';
import 'ack_waiter.dart';
import 'inbound_pipeline.dart';
import 'transport.dart';

/// Outcome of a User-IR write (upload / rename / clear).
enum IrWriteResult {
  /// Every chunk was ACKed and the pedal sent its flash-commit notification —
  /// the change persisted.
  committed,

  /// A chunk was never ACKed (transport/timeout) — the write did not go through.
  noAck,

  /// Every chunk was ACKed but the pedal never sent its commit notification.
  /// The pedal is latched in its non-committing state — a `clear` op leaves it
  /// there (verified on the wire: it blocks the official tool too) until the
  /// pedal is power-cycled — so the write was accepted but did NOT stick.
  notCommitted,
}

/// Bridges a [Transport] (USB or BLE) to the classified protocol stream.
///
/// Transport-agnostic: everything above it works in terms of [InboundMessage]s
/// and command-hex strings; the plugin-specific framing lives in the [Transport]
/// impls. Native plugin libs are loaded once at startup (`initTransports`), so
/// [startListening] is synchronous.
class DeviceService {
  DeviceService(this._transport);

  final Transport _transport;
  Stream<InboundMessage>? _inbound;
  StreamSubscription<InboundMessage>? _keepAlive;

  /// Registers the session keep-alive so the native event sink is active before
  /// any connect(), guaranteeing no device message is dropped in the startup
  /// window. Safe to call more than once.
  void startListening() {
    _keepAlive ??= inbound.listen((_) {}, onError: (_) {});
  }

  /// Kept for standalone (test) use: loads the native libs then listens.
  Future<void> init() async {
    await initTransports();
    startListening();
  }

  /// Releases the keep-alive subscription and disconnects the transport. Runs on
  /// provider dispose (a transport switch rebuilds the service), so the outgoing
  /// transport's device connection is closed rather than left open.
  Future<void> dispose() async {
    await _keepAlive?.cancel();
    await _transport.disconnect();
  }

  /// Classified inbound messages for the whole session (broadcast so multiple
  /// providers/widgets can listen). The transport supplies F0-led raw packets
  /// (and taps them for [TrafficLog]).
  Stream<InboundMessage> get inbound =>
      _inbound ??= classifyInbound(_transport.rawPackets()).asBroadcastStream();

  /// Connection-state events (true/false), or null for a transport (USB) that
  /// has none.
  Stream<bool>? get connectionEvents => _transport.connectionEvents();

  /// Connects to the pedal ([target] overrides the transport's default device).
  Future<void> connect({String? target}) => _transport.connect(target: target);

  /// Sends a stored command frame hex (the transport applies its own framing).
  Future<void> sendFrame(String frameHex) => _transport.sendFrame(frameHex);

  /// Sends [frameHex] and resolves true if the device ACKs before [timeout].
  Future<bool> sendAndAwaitAck(
    String frameHex, {
    Duration timeout = const Duration(milliseconds: 800),
  }) => awaitAck(inbound, () => sendFrame(frameHex), timeout: timeout);

  /// Serializes `DataFrame`-reading round-trips. The inbound stream carries no
  /// correlation id, so two overlapping `awaitFirst(DataFrame)` requests (e.g. a
  /// preset-state dump and a global-settings dump) would each complete on
  /// *whichever* dump arrives first — a state request could decode a global
  /// reply, or vice versa. Chaining them guarantees only one is subscribed at a
  /// time.
  Future<void> _ioGate = Future<void>.value();
  Future<T> _serialized<T>(Future<T> Function() body) {
    final result = _ioGate.then((_) => body());

    _ioGate = result.then((_) {}, onError: (_) {});

    return result;
  }

  /// Distinctive substring of the device's unsolicited IR-commit notification
  /// (`…0102010B0004…`; domain `04` = IR), sent after an IR upload / rename /
  /// clear once the flash write finishes. The `0004` domain distinguishes it
  /// from a preset commit (`…0001`).
  static const _irCommitSig = '0102010B0004';

  /// Clone/User-Profile commit notification (`…0102010B0003…`; domain `03` =
  /// User Profile, vs `04` = IR), sent after a clone-profile upload commits.
  static const _cloneCommitSig = '0102010B0003';

  /// Uploads a User-IR: sends each chunk, awaits the ACK, then the IR commit.
  Future<IrWriteResult> uploadIr(
    List<String> chunkFrames, {
    void Function(int sent, int total)? onProgress,
    Duration ackTimeout = const Duration(milliseconds: 1200),
    int ackRetries = 10,
    Duration commitTimeout = const Duration(seconds: 5),
  }) => _writeChunks(
    chunkFrames,
    _irCommitSig,
    onProgress: onProgress,
    ackTimeout: ackTimeout,
    ackRetries: ackRetries,
    commitTimeout: commitTimeout,
  );

  /// Uploads a clone profile (`.clo`) into a User-Profile slot: same chunked
  /// transport as [uploadIr], but awaits the clone commit ([_cloneCommitSig]).
  Future<IrWriteResult> uploadClone(
    List<String> chunkFrames, {
    void Function(int sent, int total)? onProgress,
    Duration ackTimeout = const Duration(milliseconds: 1200),
    int ackRetries = 10,
    Duration commitTimeout = const Duration(seconds: 5),
  }) => _writeChunks(
    chunkFrames,
    _cloneCommitSig,
    onProgress: onProgress,
    ackTimeout: ackTimeout,
    ackRetries: ackRetries,
    commitTimeout: commitTimeout,
  );

  /// Sends each chunk frame and waits for the device's ACK before the next
  /// (retransmitting a dropped ACK), reporting progress via [onProgress], then
  /// waits for the device's commit notification matching [commitSig]. Returns an
  /// [IrWriteResult] (committed / no-ACK / accepted-but-not-committed).
  /// Serialized against other round-trips — the pedal handles one at a time.
  Future<IrWriteResult> _writeChunks(
    List<String> chunkFrames,
    String commitSig, {
    void Function(int sent, int total)? onProgress,
    Duration ackTimeout = const Duration(milliseconds: 1200),
    int ackRetries = 10,
    Duration commitTimeout = const Duration(seconds: 5),
  }) => _serialized(() async {
    final total = chunkFrames.length;

    for (final (i, frame) in chunkFrames.indexed) {
      // The pedal intermittently drops a single chunk's ACK. The official tool
      // tolerates a multi-second stall and RETRANSMITS the same seq (the device
      // accepts the duplicate) instead of aborting; a partial blob is never
      // committed. Mirror that: re-send on timeout up to [ackRetries] times so
      // one dropped ACK can't silently truncate the upload.
      var acked = false;

      for (var attempt = 0; attempt < ackRetries && !acked; attempt++) {
        acked = await sendAndAwaitAck(frame, timeout: ackTimeout);
      }

      if (!acked) return .noAck;

      onProgress?.call(i + 1, total);
    }

    // The pedal commits asynchronously (a flash write, ~2-3s) and signals
    // completion with an unsolicited notification. Wait for it: its arrival is
    // the only proof the change actually persisted. If it never comes, every
    // chunk was ACKed but the pedal is latched in its non-committing state (a
    // `clear` leaves it there until a power-cycle) — the write did not stick, so
    // the caller can tell the user rather than falsely report success.
    final committed = await awaitFirst<bool>(
      inbound,
      () async {},
      (m) => m is DataFrame && m.hex.toUpperCase().contains(commitSig)
          ? true
          : null,
      timeout: commitTimeout,
    );

    return (committed ?? false) ? .committed : .notCommitted;
  });

  /// Session-init request (`020300`) the official tool sends first on connect.
  /// It is a precondition for the pedal to commit User-IR writes to flash:
  /// without it, upload/rename/clear are ACKed but never committed (no
  /// `0102010B0004`), so changes don't persist. Best-effort; returns the
  /// reassembled response (device replies `1130…`), or null on timeout.
  static const _sessionInitRequest = '8080F0050900010000000201020300F7';
  Future<String?> enterEditSession({
    Duration timeout = const Duration(seconds: 1),
  }) => _serialized(
    () => awaitFirst<String>(
      inbound,
      () => sendFrame(_sessionInitRequest),
      (m) => m is DataFrame ? m.hex : null,
      timeout: timeout,
    ),
  );

  /// Request current preset state (`020401`) and returns the reassembled dump
  /// frame hex, or null on timeout.
  static const _stateRequest = '8080F0000900010000000201020401F7';
  Future<String?> requestStateDump({
    Duration timeout = const Duration(seconds: 1),
  }) => _serialized(
    () => awaitFirst<String>(
      inbound,
      () => sendFrame(_stateRequest),
      (m) => m is DataFrame ? m.hex : null,
      timeout: timeout,
    ),
  );

  /// Request the device-global settings dump (`020102 0100`); returns the
  /// reassembled frame hex, or null on timeout.
  static const _globalRequest = '8080F00B0900010000000201020100F7';
  Future<String?> requestGlobalSettings({
    Duration timeout = const Duration(seconds: 1),
  }) => _serialized(
    () => awaitFirst<String>(
      inbound,
      () => sendFrame(_globalRequest),
      (m) => m is DataFrame ? m.hex : null,
      timeout: timeout,
    ),
  );

  /// Request all 100 preset names (`020400`); returns the reassembled dump
  /// frame hex, or null on timeout. One reassembled DataFrame (verified live).
  static const _presetNamesRequest = '8080F0000E00010000000201020400F7';
  Future<String?> requestPresetNames({
    Duration timeout = const Duration(seconds: 2),
  }) => _serialized(
    () => awaitFirst<String>(
      inbound,
      () => sendFrame(_presetNamesRequest),
      (m) => m is DataFrame ? m.hex : null,
      timeout: timeout,
    ),
  );

  /// Request a 5-slot user-name dump — [requestHex] is [cloneNamesRequest]
  /// (User Profiles) or [irNamesRequest] (User IRs). Returns the reassembled
  /// frame hex, or null on timeout. Serialized against other DataFrame reads.
  static const cloneNamesRequest = '8080F0030500010000000201020204F7';
  static const irNamesRequest = '8080F0020900010000000201020200F7';
  Future<String?> requestUserNames(
    String requestHex, {
    Duration timeout = const Duration(seconds: 1),
  }) => _serialized(
    () => awaitFirst<String>(
      inbound,
      () => sendFrame(requestHex),
      (m) => m is DataFrame ? m.hex : null,
      timeout: timeout,
    ),
  );

  Future<void> disconnect() => _transport.disconnect();
}
