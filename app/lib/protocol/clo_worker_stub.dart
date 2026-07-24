import 'dart:typed_data';

import 'clo_worker_data.dart';

/// Non-web stub for [convertNamInWorker]. The Web Worker path is only reachable
/// under dart2js; desktop/mobile use the native flutter_rust_bridge generator
/// instead, so this is never invoked — it exists only so the conditional export
/// in `clo_worker.dart` type-checks off the web.
Future<CloArraysData> convertNamInWorker(String namJson, Float32List di) {
  throw UnsupportedError('convertNamInWorker is only available on Flutter Web');
}
