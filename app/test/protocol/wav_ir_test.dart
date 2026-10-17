import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/ir_upload_frame.dart';
import 'package:sonicmaster/protocol/wav_ir.dart';

void main() {
  test('44100 mono impulse → verbatim int24, fixed 512 taps', () {
    final wav = _wav16(rate: 44100, pcm: [32767, ...List.filled(511, 0)]);
    final samples = WavIr.toDeviceSamples(wav);

    expect(samples.length, IrUploadFrame.deviceTaps);
    // 32767/32768 × 8388607 = 8388351 (matches the captured tool output).
    expect(samples[0], 8388351);
    expect(samples.sublist(1), everyElement(0));
  });

  test('48000 input is resampled but still 512 taps', () {
    final wav = _wav16(rate: 48000, pcm: [32767, ...List.filled(511, 0)]);
    final samples = WavIr.toDeviceSamples(wav);

    expect(samples.length, IrUploadFrame.deviceTaps);
    expect(samples[0], greaterThan(8000000));
  });

  test('short input is zero-padded to 512 taps', () {
    final wav = _wav16(rate: 44100, pcm: List.filled(64, 0));
    final samples = WavIr.toDeviceSamples(wav);

    expect(samples.length, IrUploadFrame.deviceTaps);
    expect(samples, everyElement(0));
  });

  test('stereo is averaged to mono', () {
    // Interleaved L/R: L=full-scale, R=0 → mono ≈ half-scale at sample 0.
    final wav = _wav16(
      rate: 44100,
      channels: 2,
      pcm: [32767, 0, ...List.filled(1022, 0)],
    );
    final samples = WavIr.toDeviceSamples(wav);

    expect(samples.length, IrUploadFrame.deviceTaps);
    expect(samples[0], closeTo(8388351 ~/ 2, 2));
  });

  test('full WAV → upload chunks are well-formed', () {
    final wav = _wav16(rate: 44100, pcm: [32767, ...List.filled(511, 0)]);
    final samples = WavIr.toDeviceSamples(wav);
    final chunks = IrUploadFrame.buildChunks(
      IrUploadFrame.buildBlob(slot: 3, name: 'test', samples: samples),
    );

    expect(chunks.length, 112);
    expect(chunks.every((c) => c.startsWith('8080F0') && c.endsWith('F7')), isTrue);
  });

  test('rejects non-WAV bytes', () {
    expect(
      () => WavIr.parse(Uint8List.fromList([0, 1, 2, 3])),
      throwsFormatException,
    );
  });
}

/// Builds a minimal 16-bit PCM WAV. [pcm] is interleaved by channel.
Uint8List _wav16({
  required int rate,
  required List<int> pcm,
  int channels = 1,
}) {
  final dataBytes = pcm.length * 2;

  List<int> u32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
  List<int> u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ...u32(36 + dataBytes),
    ...'WAVE'.codeUnits,
    ...'fmt '.codeUnits,
    ...u32(16),
    ...u16(1), // PCM
    ...u16(channels),
    ...u32(rate),
    ...u32(rate * channels * 2),
    ...u16(channels * 2),
    ...u16(16),
    ...'data'.codeUnits,
    ...u32(dataBytes),
    ...pcm.expand((s) => u16(s & 0xFFFF)),
  ]);
}
