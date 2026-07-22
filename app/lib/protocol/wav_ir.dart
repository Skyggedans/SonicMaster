import 'dart:typed_data';

import 'ir_upload_frame.dart';

/// Decoded PCM/float WAV audio, downmixed to mono in the range −1.0…1.0.
class WavAudio {
  const WavAudio({required this.rate, required this.mono});

  final int rate;
  final List<double> mono;
}

/// Reads a WAV file and converts it to the pedal's User-IR sample format:
/// resample to [IrUploadFrame.deviceRate], fit to [IrUploadFrame.deviceTaps],
/// and scale to int24 (`round(sample × fullScale)`, clamped).
///
/// A simple linear resampler is used — the device also resamples internally, so
/// only the rate/length/scale contract must hold; higher-quality resampling is a
/// later refinement.
class WavIr {
  /// Full WAV bytes → exactly [IrUploadFrame.deviceTaps] int24 samples.
  static List<int> toDeviceSamples(Uint8List wavBytes) {
    final audio = parse(wavBytes);

    final resampled = _resampleLinear(
      audio.mono,
      audio.rate,
      IrUploadFrame.deviceRate,
    );

    final fitted = List<double>.generate(
      IrUploadFrame.deviceTaps,
      (i) => i < resampled.length ? resampled[i] : 0.0,
    );

    const fs = IrUploadFrame.fullScale;

    return fitted
        .map((s) => (s * fs).round().clamp(-fs, fs))
        .toList(growable: false);
  }

  /// Parses a RIFF/WAVE file into mono float samples. Supports PCM int
  /// 8/16/24/32-bit and IEEE float32; multi-channel is averaged to mono.
  static WavAudio parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);

    if (bytes.length < 12 ||
        _tag(bytes, 0) != 'RIFF' ||
        _tag(bytes, 8) != 'WAVE') {
      throw const FormatException('not a WAV file');
    }

    var format = 1;
    var channels = 1;
    var rate = IrUploadFrame.deviceRate;
    var bits = 16;
    var dataOffset = -1;
    var dataSize = 0;

    var off = 12;

    while (off + 8 <= bytes.length) {
      final id = _tag(bytes, off);
      final size = data.getUint32(off + 4, Endian.little);
      final body = off + 8;

      if (id == 'fmt ' && body + 16 <= bytes.length) {
        format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        rate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        dataOffset = body;
        dataSize = size;
      }

      off = body + size + (size & 1); // chunks are word-aligned
    }

    if (dataOffset < 0) {
      throw const FormatException('WAV has no data chunk');
    }

    // Guard the sample rate before it drives the resampler ratio — a bogus rate
    // from a malformed header would otherwise size the output buffer wildly (OOM
    // / freeze). 8–192 kHz covers every real capture.
    if (rate < 8000 || rate > 192000) {
      throw FormatException('unsupported WAV sample rate: $rate Hz');
    }

    final available = (bytes.length - dataOffset).clamp(0, dataSize);

    return WavAudio(
      rate: rate,
      mono: _decodeMono(data, dataOffset, available, channels, bits, format),
    );
  }

  static List<double> _decodeMono(
    ByteData data,
    int offset,
    int size,
    int channels,
    int bits,
    int format,
  ) {
    final bytesPerSample = bits ~/ 8;
    final frameBytes = bytesPerSample * channels;

    if (frameBytes == 0) return const [];

    final frames = size ~/ frameBytes;

    return List<double>.generate(frames, (f) {
      final base = offset + f * frameBytes;
      final sum = Iterable<int>.generate(channels).fold<double>(
        0.0,
        (acc, ch) =>
            acc + _sampleAt(data, base + ch * bytesPerSample, bits, format),
      );

      return sum / channels;
    });
  }

  static double _sampleAt(ByteData data, int p, int bits, int format) {
    switch (bits) {
      case 8:
        return (data.getUint8(p) - 128) / 128.0;
      case 16:
        return data.getInt16(p, Endian.little) / 32768.0;
      case 24:
        final v =
            data.getUint8(p) |
            (data.getUint8(p + 1) << 8) |
            (data.getUint8(p + 2) << 16);

        return (v & 0x800000 != 0 ? v - 0x1000000 : v) / 8388608.0;
      case 32:
        return format == 3
            ? data.getFloat32(p, Endian.little)
            : data.getInt32(p, Endian.little) / 2147483648.0;
      default:
        throw FormatException('unsupported WAV bit depth: $bits');
    }
  }

  static List<double> _resampleLinear(List<double> src, int from, int to) {
    if (from == to || src.isEmpty) return src;

    final outN = (src.length * to / from).round();

    return List<double>.generate(outN, (i) {
      final pos = i * from / to;
      final lo = pos.floor();
      final frac = pos - lo;
      final a = lo < src.length ? src[lo] : 0.0;
      final b = lo + 1 < src.length ? src[lo + 1] : 0.0;

      return a + (b - a) * frac;
    });
  }

  static String _tag(Uint8List b, int off) =>
      String.fromCharCodes(b.sublist(off, off + 4));
}
