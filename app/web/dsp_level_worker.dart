// Web Worker entry point for ONE probe level of the pure-Dart `.nam` -> `.clo`
// DSP.
//
// Compiled standalone with
//   `dart compile js web/dsp_level_worker.dart -o web/dsp_level_worker.dart.js`
// (see `tools/build_web.sh`) and loaded from the app by `clo_worker_web.dart`
// via `Worker('dsp_level_worker.dart.js')`. dart2js has no isolate workers, so a
// real JS Web Worker is the only way to keep the WaveNet inference off the
// Flutter UI thread — and running one level per worker lets the ~5 independent
// probe passes run concurrently across a worker pool (~4-5x faster overall).
//
// Message protocol (one level per message; workers are reused across levels):
//   in : { namJson: String, di: Float32Array, level: Number }
//   out: { level: Number, response: Float64Array }
//        or, on failure: { error: String, level: Number }
// The response buffer is posted back as a transferable (zero-copy handoff). The
// DI is resampled locally in each worker (redundant but off-main and cheap
// relative to the WaveNet), so the UI thread never runs the heavy resample.

import 'dart:js_interop';

import 'package:sonicmaster/protocol/clo_dsp.dart';
import 'package:web/web.dart' show DedicatedWorkerGlobalScope, MessageEvent;

@JS('self')
external DedicatedWorkerGlobalScope get _self;

extension type _Request(JSObject _) implements JSObject {
  external String get namJson;
  external JSFloat32Array get di;
  external double get level;
}

extension type _Response._(JSObject _) implements JSObject {
  external factory _Response({double level, JSFloat64Array response});
}

extension type _ErrorResponse._(JSObject _) implements JSObject {
  external factory _ErrorResponse({String error, double level});
}

extension type _Transferable(JSObject _) implements JSObject {
  external JSArrayBuffer get buffer;
}

void main() {
  _self.onmessage = ((MessageEvent event) {
    final request = _Request(event.data as JSObject);
    final level = request.level;

    try {
      final di = request.di.toDart;
      final response = runOneProbeLevel(request.namJson, di, level).toJS;

      final message = _Response(level: level, response: response);
      final transfer = <JSObject>[_Transferable(response).buffer].toJS;

      _self.postMessage(message, transfer);
    } catch (e) {
      _self.postMessage(_ErrorResponse(error: e.toString(), level: level));
    }
  }).toJS;
}
