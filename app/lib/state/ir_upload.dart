import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_service.dart';
import '../protocol/ir_upload_frame.dart';
import '../protocol/wav_ir.dart';
import 'device_providers.dart';
import 'preset_providers.dart';

/// Picks a WAV file and uploads it into User-IR [slot] (0-based, 0..4 = User IR
/// 1..5) on the connected pedal, then refreshes the slot names. Reuses the
/// shared preset status/loading providers for feedback. No-op if a load is
/// already in flight or the user cancels.
Future<void> uploadIrFromFile(WidgetRef ref, int slot) async {
  if (ref.read(presetLoadingProvider)) return;

  final status = ref.read(presetLoadStatusProvider.notifier);

  final Uint8List bytes;
  final String fileName;

  try {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Load IR into User IR ${slot + 1}',
      type: .custom,
      allowedExtensions: const ['wav'],
      withData: true,
    );

    final picked = res?.files.single;
    final data = picked?.bytes;

    if (data == null) return; // cancelled

    bytes = data;
    fileName = picked!.name;
  } catch (e) {
    status.state = 'IR load failed: $e';

    return;
  }

  final String name;
  final List<String> chunks;

  try {
    final samples = WavIr.toDeviceSamples(bytes);

    name = _slotName(fileName);
    chunks = IrUploadFrame.buildChunks(
      IrUploadFrame.buildBlob(slot: slot, name: name, samples: samples),
    );
  } catch (e) {
    status.state = 'IR decode failed: $e';

    return;
  }

  ref.read(presetLoadingProvider.notifier).state = true;

  try {
    final result = await _writeIrSlot(
      ref,
      chunks,
      onProgress: (sent, total) => status.state = 'uploading IR… $sent/$total',
    );

    status.state = switch (result) {
      .committed => 'IR "$name" → User IR ${slot + 1}',
      .noAck => 'IR upload failed (no ACK)',
      .notCommitted =>
        'IR sent but not saved — power-cycle the pedal, then retry',
    };
  } catch (e) {
    status.state = 'IR upload failed: $e';
  } finally {
    ref.read(presetLoadingProvider.notifier).state = false;
  }
}

/// Renames User-IR [slot] (0-based) to [name] on the connected pedal (a short
/// 2-chunk command; the IR audio is untouched), then refreshes the slot names.
Future<void> renameIrSlot(WidgetRef ref, int slot, String name) =>
    _runIrCommand(
      ref,
      IrUploadFrame.buildChunks(
        IrUploadFrame.buildRenameBlob(slot: slot, name: name),
      ),
      busy: 'renaming…',
      done: 'renamed User IR ${slot + 1}',
    );

/// Clears User-IR [slot] (0-based) on the connected pedal, then refreshes the
/// slot names.
Future<void> clearIrSlot(WidgetRef ref, int slot) => _runIrCommand(
  ref,
  IrUploadFrame.buildChunks(IrUploadFrame.buildClearBlob(slot: slot)),
  busy: 'clearing…',
  done: 'cleared User IR ${slot + 1} — power-cycle before the next IR edit',
);

/// Sends a small chunked User-IR command (rename/clear) with the same commit
/// flow as an upload. No-op if a load is in flight.
Future<void> _runIrCommand(
  WidgetRef ref,
  List<String> chunks, {
  required String busy,
  required String done,
}) async {
  if (ref.read(presetLoadingProvider)) return;

  final status = ref.read(presetLoadStatusProvider.notifier);

  ref.read(presetLoadingProvider.notifier).state = true;

  try {
    status.state = busy;
    final result = await _writeIrSlot(ref, chunks);

    status.state = switch (result) {
      .committed => done,
      .noAck => 'IR command failed (no ACK)',
      .notCommitted => 'not saved — power-cycle the pedal, then retry',
    };
  } catch (e) {
    status.state = 'IR command failed: $e';
  } finally {
    ref.read(presetLoadingProvider.notifier).state = false;
  }
}

/// Writes [chunks] to a User-IR slot, byte-for-byte mirroring the official
/// tool's write-time sequence: read IR names to enter IR context (`020200`), the
/// chunks, then await the flash commit, then refresh the names. It does NOT
/// re-enter the edit session (`020300`) here — the tool opens it once on connect
/// (see [connectAndSync]) and never re-sends it around a write.
///
/// Whether the pedal actually commits is device state, not the wire: after a
/// `clear` op the pedal latches into a non-committing state (proven on the wire —
/// it then blocks the official tool too) until a power-cycle. This surfaces as
/// [IrWriteResult.notCommitted]. Returns the write outcome.
Future<IrWriteResult> _writeIrSlot(
  WidgetRef ref,
  List<String> chunks, {
  void Function(int sent, int total)? onProgress,
}) async {
  await refreshIrNames(ref); // 020200 — enter IR context (as the tool does)

  final service = ref.read(deviceServiceProvider);

  final result = await service.uploadIr(chunks, onProgress: onProgress);

  await refreshIrNames(ref);

  return result;
}

/// The pedal stores a 10-char name; the tool derives it from the file name
/// (extension dropped). [IrUploadFrame] truncates to the 10-char limit.
String _slotName(String fileName) {
  final dot = fileName.lastIndexOf('.');

  return dot > 0 ? fileName.substring(0, dot) : fileName;
}
