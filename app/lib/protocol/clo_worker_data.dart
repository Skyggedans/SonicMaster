import 'dart:typed_data';

/// The clone-model arrays returned by the Web Worker DSP path: the two FIR
/// arrays plus the saturator gains, ready to wrap in a `CloProfile`. Mirrors the
/// `CloArrays` shape from `clo_dsp.dart` but lives in its own tiny, import-free
/// library so both the web helper and the desktop stub can share the type.
class CloArraysData {
  const CloArraysData({
    required this.arrayA,
    required this.arrayB,
    required this.gains,
  });

  final Float32List arrayA; // 128-tap pre-filter (input EQ)
  final Float32List arrayB; // 2048-tap post-filter (amp + cab)
  final List<double> gains; // [posmax, negmax, pos_rate, neg_rate]
}
