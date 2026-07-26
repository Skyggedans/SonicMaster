import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Throwaway MIDI traffic capture for protocol reverse-engineering (Phase 0 of
/// the tuner-command hunt).
///
/// Off by default. Flip [isEnabled] — compile-time via
/// `--dart-define=MIDI_CAPTURE=true`, or at runtime from the dev console — to
/// mirror every RX/TX frame, plus manual [marker]s, into a capture file and the
/// debug console. It records bytes verbatim (no framing) so a session can be
/// diffed against the known command map; it is not part of the shipping
/// protocol layer.
class TrafficLog {
  TrafficLog._();

  /// Whether capture is active. Defaults to the `MIDI_CAPTURE` dart-define so
  /// production builds never touch the disk; the dev console can toggle it.
  static bool isEnabled = const bool.fromEnvironment('MIDI_CAPTURE');

  static IOSink? _sink;
  static Future<void>? _opening;
  static String? _path;

  /// Absolute path of the current capture file, once opened (`null` until the
  /// first line is written).
  static String? get path => _path;

  /// Records one frame going in direction [dir] (`'RX'` or `'TX'`). No-op when
  /// disabled, so it is cheap to leave on the hot path.
  static void record(String dir, List<int> bytes) {
    if (!isEnabled) return;

    _emit(formatLine(DateTime.now(), dir, bytes));
  }

  /// Records a manual marker line (e.g. `'enter tuner'`) to delimit an
  /// experiment window. No-op when disabled.
  static void marker(String label) {
    if (!isEnabled) return;

    _emit(formatLine(DateTime.now(), 'MARK', const [], note: label));
  }

  /// Pure, testable line format: `<iso8601>  <DIR>  <n>B  <HEX>[  <note>]`.
  static String formatLine(
    DateTime at,
    String dir,
    List<int> bytes, {
    String? note,
  }) {
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();

    final body =
        '${at.toIso8601String()}  ${dir.padRight(4)}  '
        '${bytes.length}B  $hex';

    return note == null ? body : '$body  $note';
  }

  /// Ensures the capture file is open and returns its path (for the UI to show
  /// where a session is being written).
  static Future<String?> ensureFile() async {
    await _ensureSink();

    return _path;
  }

  /// Flushes and closes the capture file. Safe to call when disabled.
  static Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _opening = null;
  }

  static void _emit(String line) {
    debugPrint('[midi] $line');
    // Fire-and-forget; lines preserve call order because the open future is
    // memoized and its continuations run FIFO.
    _writeFile(line);
  }

  static Future<void> _writeFile(String line) async {
    final sink = await _ensureSink();

    sink?.writeln(line);
  }

  static Future<IOSink?> _ensureSink() async {
    if (_sink != null) return _sink;

    _opening ??= _open();
    await _opening;

    return _sink;
  }

  static Future<void> _open() async {
    try {
      final dir = await getApplicationSupportDirectory();

      // Stable name in append mode: re-enabling within a run keeps history;
      // markers delimit sessions.
      _path = '${dir.path}/midi-capture.log';
      _sink = File(_path!).openWrite(mode: FileMode.append);
    } catch (e) {
      debugPrint('[midi] capture file open failed: $e');
    }
  }
}
