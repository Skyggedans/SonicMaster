#!/usr/bin/env bash
#
# Builds the Flutter Web bundle together with the DSP Web Worker.
#
# The worker is a SEPARATE Dart entry point (web/dsp_level_worker.dart) — `flutter
# build web` only compiles lib/main.dart, so it never reaches the worker. We
# compile it explicitly to web/dsp_level_worker.dart.js first; because it already
# lives under web/, the subsequent `flutter build web` copies the emitted JS into
# build/web/ alongside main.dart.js, where `Worker('dsp_level_worker.dart.js')`
# loads it at runtime (see lib/protocol/clo_worker_web.dart). The coordinator
# spawns a pool of these, one probe level per worker, to parallelize the WaveNet.
#
# (dart2wasm for the worker was tried and is SLOWER than dart2js for this
# WaveNet-inference workload, so the worker stays on dart2js.)
#
# Run from anywhere; paths are resolved relative to the app dir.
set -euo pipefail

cd "$(dirname "$0")/.."

echo '==> Compiling DSP web worker -> web/dsp_level_worker.dart.js'
dart compile js web/dsp_level_worker.dart -o web/dsp_level_worker.dart.js

echo '==> Building Flutter web bundle (--no-tree-shake-icons)'
# Extra args are forwarded to `flutter build web` (e.g. --base-href /SonicMaster/
# for GitHub Pages project sites).
flutter build web --no-tree-shake-icons "$@"

echo '==> Done. Worker bundled at build/web/dsp_level_worker.dart.js'
