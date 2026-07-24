import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sonicmaster/protocol/clo_dsp.dart';
import 'package:web/web.dart' show Event, MessageEvent, Worker, window;

import 'clo_worker_data.dart';

extension type _Request._(JSObject _) implements JSObject {
  external factory _Request({String namJson, JSFloat32Array di, double level});
}

extension type _Response(JSObject _) implements JSObject {
  external String? get error;
  external double get level;
  external JSFloat64Array? get response;
}

/// Runs the pure-Dart `.nam` -> `.clo` DSP across a pool of dedicated Web Workers
/// so the ~150 s WaveNet inference never blocks the Flutter UI isolate (dart2js
/// has no isolate workers of its own). The dominant cost is the independent
/// per-level probe passes ([cloProbeLevels]); those are fanned out one level per
/// worker across up to `min(hardwareConcurrency, 6)` workers (~4-5x faster), then
/// the cheap finishing fit ([finishFromProbeResponses]) runs here on the UI
/// isolate. Each worker gets its own copy of the raw reference DI (posted by
/// structured clone, not transferred) and resamples it locally, keeping the heavy
/// resample off the main thread.
Future<CloArraysData> convertNamInWorker(String namJson, Float32List di) {
  final completer = Completer<CloArraysData>();
  final levels = cloProbeLevels;

  // N = clamp(levels, 1, min(hardwareConcurrency ?? 4, 6)).
  final concurrency = window.navigator.hardwareConcurrency;
  final cap = math.min(concurrency >= 1 ? concurrency : 4, 6);
  final poolSize = levels.length.clamp(1, cap);

  // A single JS view over the DI, reused for every send. Because we never pass it
  // as a transferable, each postMessage structured-clones a fresh copy into the
  // worker and the source stays valid for the next dispatch.
  final jsDi = di.toJS;
  final responses = <(double, Float64List)>[];
  final workers = <Worker>[];

  var nextLevel = 0;
  var isDone = false;

  void terminateAll() {
    for (final worker in workers) {
      worker.terminate();
    }
  }

  void fail(Object error) {
    if (isDone) return;

    isDone = true;
    terminateAll();
    completer.completeError(error);
  }

  void dispatchNext(Worker worker) {
    if (nextLevel >= levels.length) return;

    final level = levels[nextLevel++];
    final request = _Request(namJson: namJson, di: jsDi, level: level);

    worker.postMessage(request);
  }

  void handleMessage(Worker worker, MessageEvent event) {
    if (isDone) return;

    final response = _Response(event.data as JSObject);
    final error = response.error;

    if (error != null) {
      fail(StateError('dsp_level_worker (level ${response.level}): $error'));

      return;
    }

    responses.add((response.level, response.response!.toDart));

    if (responses.length == levels.length) {
      isDone = true;
      terminateAll();

      final arrays = finishFromProbeResponses(namJson, di, responses);

      completer.complete(
        CloArraysData(
          arrayA: arrays.arrayA,
          arrayB: arrays.arrayB,
          gains: arrays.gains,
        ),
      );

      return;
    }

    // This worker is free — hand it the next queued level (level count may
    // exceed the pool size, so workers are reused until the queue drains).
    dispatchNext(worker);
  }

  for (final _ in Iterable<int>.generate(poolSize)) {
    final worker = Worker('dsp_level_worker.dart.js'.toJS);

    worker.onmessage = ((MessageEvent event) => handleMessage(
      worker,
      event,
    )).toJS;
    worker.onerror = ((Event event) => fail(
      StateError('dsp_level_worker failed to run'),
    )).toJS;

    workers.add(worker);
  }

  for (final worker in workers) {
    dispatchNext(worker);
  }

  return completer.future;
}
