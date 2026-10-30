// Faithfulness check for the parallel decomposition: computing each probe level
// via `runOneProbeLevel` and reassembling with `finishFromProbeResponses` must
// reproduce the all-in-one `generateCloArraysDart` element-wise. This is what the
// Web Worker path relies on — the workers only relocate `runOneProbeLevel`, so if
// the in-process split is exact, the parallel result is exact too.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/clo_dsp.dart';

// Paths relative to the app/ package root (flutter test's working directory).
// ac30_full.nam is a large, gitignored local fixture — see the skip guard below.
const _namPath = 'rust/tests/fixtures/ac30_full.nam';
const _diPath = 'assets/data/nam_reference_di_44100.f32';

Float32List _loadF32(String path) {
  final bytes = File(path).readAsBytesSync();

  return Float32List.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ 4,
  );
}

double _maxAbsDiff(List<double> a, List<double> b) {
  var m = 0.0;

  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();

    if (d > m) {
      m = d;
    }
  }

  return m;
}

void main() {
  // ac30_full.nam is gitignored (the fixtures dir holds ~50 MB of local test
  // data), so skip where it is absent (CI, fresh clones) rather than fail;
  // present locally, the full split-equivalence runs.
  final skip = File(_namPath).existsSync()
      ? false
      : 'DSP fixture $_namPath not present (local-only)';

  test(
    'split (runOneProbeLevel + finishFromProbeResponses) == generateCloArraysDart',
    () {
      final namJson = File(_namPath).readAsStringSync();
      final di = _loadF32(_diPath);

      final full = generateCloArraysDart(namJson, di);

      // Drive the decomposition exactly as the parallel worker path will: one
      // self-contained `runOneProbeLevel` per level, then a single finishing fit.
      final responses = cloProbeLevels
          .map((level) => (level, runOneProbeLevel(namJson, di, level)))
          .toList();

      // Time the finishing fit alone — it runs on the UI thread in the web path,
      // so it must be cheap relative to the (now parallelized) probe passes.
      final sw = Stopwatch()..start();
      final split = finishFromProbeResponses(namJson, di, responses);

      sw.stop();

      // ignore: avoid_print
      print('finishFromProbeResponses took ${sw.elapsedMilliseconds} ms');

      expect(split.arrayA.length, full.arrayA.length);
      expect(split.arrayB.length, full.arrayB.length);
      expect(split.gains.length, full.gains.length);

      final diffA = _maxAbsDiff(split.arrayA, full.arrayA);
      final diffB = _maxAbsDiff(split.arrayB, full.arrayB);
      final diffG = _maxAbsDiff(split.gains, full.gains);

      // ignore: avoid_print
      print('split maxAbsDiff  arrayA=$diffA  arrayB=$diffB  gains=$diffG');

      // The split is the same computation reordered across workers: arrayA and
      // the gains must match to the bit; arrayB within a hair (1e-9) to absorb
      // any FP associativity wobble in the fit.
      expect(diffA, 0.0, reason: 'arrayA must be bit-exact');
      expect(diffG, 0.0, reason: 'gains must be bit-exact');
      expect(diffB, lessThanOrEqualTo(1e-9), reason: 'arrayB within 1e-9');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
