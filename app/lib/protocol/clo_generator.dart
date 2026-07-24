import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

import '../src/rust/api/generator.dart';
import 'clo_codec.dart';
import 'clo_worker.dart';

/// Generates a clone-model [CloProfile] from a `.nam` amp profile, natively —
/// the open-source replacement for the vendor DLL's `namConvertCloData`. The
/// heavy DSP (WaveNet inference + Wiener post-filter design) runs in Rust
/// ([generateCloArrays]); this wraps the result in the pedal's `.clo` model.
class CloGenerator {
  /// The fixed reference DI the amp model is probed with (mono, 44.1 kHz f32),
  /// identical to the one the official tool bundles.
  static const _referenceDiAsset = 'assets/data/nam_reference_di_44100.f32';

  /// The DC-block biquad `[b0, b1, b2, a1, a2]` the tool embeds in every `.clo`
  /// (a fixed 2nd-order Butterworth high-pass, rate-mode-selected for 48 kHz).
  static const _biquad = <double>[
    0.9963043928146362,
    -1.9926087856292725,
    0.9963043928146362,
    -1.9925950765609741,
    0.9926224946975708,
  ];

  const CloGenerator();

  /// Converts [namJson] (a classic NAM WaveNet `.nam`, as JSON text) into a
  /// [CloProfile]. Runs off the UI thread inside the Rust bridge.
  Future<CloProfile> fromNam(String namJson) async {
    final di = await _loadReferenceDi();

    // Web uses the pure-Dart DSP port (the flutter_rust_bridge WASM path traps
    // at module instantiation in RustLib.init()), run inside a Web Worker so the
    // ~140 s WaveNet inference stays off the UI isolate — dart2js has no isolate
    // workers of its own. Desktop uses the native, threaded Rust generator. Both
    // are numerically bit-exact.
    if (kIsWeb) {
      final arrays = await convertNamInWorker(namJson, di);

      return CloProfile(
        biquad: _biquad,
        gains: arrays.gains,
        arrayA: arrays.arrayA,
        arrayB: arrays.arrayB,
      );
    }

    final arrays = await generateCloArrays(
      namJson: namJson,
      referenceDi44100: di,
    );

    return CloProfile(
      biquad: _biquad,
      gains: arrays.gains,
      arrayA: arrays.arrayA,
      arrayB: arrays.arrayB,
    );
  }

  Future<Float32List> _loadReferenceDi() async {
    final data = await rootBundle.load(_referenceDiAsset);

    return data.buffer.asFloat32List(
      data.offsetInBytes,
      data.lengthInBytes ~/ 4,
    );
  }
}
