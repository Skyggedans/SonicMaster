// Parity check: the pure-Dart `generateCloArraysDart` must reproduce the native
// Rust `generateCloArrays` element-wise. The native golden (arrayA/arrayB/gains
// as f32 LE) was captured into `test/fixtures/clo_native_golden.bin`; this runs
// the Dart port over the same fixture .nam + reference DI and asserts a tight
// per-element and sum tolerance.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/clo_dsp.dart';

// Paths relative to the app/ package root (flutter test's working directory).
// ac30_full.nam is a large, gitignored local fixture — see the skip guard below.
const _namPath = 'rust/tests/fixtures/ac30_full.nam';
const _diPath = 'assets/data/nam_reference_di_44100.f32';
const _goldenPath = 'test/fixtures/clo_native_golden.bin';

Float32List _loadF32(String path) {
  final bytes = File(path).readAsBytesSync();

  return Float32List.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ 4,
  );
}

double _sum(List<double> a) => a.fold(0.0, (s, v) => s + v);

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
  // present locally, the full parity runs.
  final skip = File(_namPath).existsSync()
      ? false
      : 'DSP parity fixture $_namPath not present (local-only)';

  test(
    'Dart clo_dsp matches native golden',
    () {
      final golden = _loadF32(_goldenPath);
      final goldA = Float32List.view(golden.buffer, golden.offsetInBytes, 128);
      final goldB = Float32List.view(
        golden.buffer,
        golden.offsetInBytes + 128 * 4,
        2048,
      );
      final goldG = Float32List.view(
        golden.buffer,
        golden.offsetInBytes + (128 + 2048) * 4,
        4,
      );

      final namJson = File(_namPath).readAsStringSync();
      final di = _loadF32(_diPath);

      final result = generateCloArraysDart(namJson, di);

      expect(result.arrayA.length, 128);
      expect(result.arrayB.length, 2048);
      expect(result.gains.length, 4);

      final diffA = _maxAbsDiff(result.arrayA, goldA);
      final diffB = _maxAbsDiff(result.arrayB, goldB);
      final diffG = _maxAbsDiff(result.gains, goldG);
      final sumA = (_sum(result.arrayA) - _sum(goldA)).abs();
      final sumB = (_sum(result.arrayB) - _sum(goldB)).abs();
      final sumG = (_sum(result.gains) - _sum(goldG)).abs();

      // ignore: avoid_print
      print('maxAbsDiff  arrayA=$diffA  arrayB=$diffB  gains=$diffG');
      // ignore: avoid_print
      print('sumDiff     arrayA=$sumA  arrayB=$sumB  gains=$sumG');

      expect(diffA, lessThan(1e-3), reason: 'arrayA element diff too large');
      expect(diffB, lessThan(1e-3), reason: 'arrayB element diff too large');
      expect(diffG, lessThan(1e-3), reason: 'gains element diff too large');
      expect(sumA, lessThan(1e-3), reason: 'arrayA sum diff too large');
      expect(sumB, lessThan(1e-3), reason: 'arrayB sum diff too large');
      expect(sumG, lessThan(1e-3), reason: 'gains sum diff too large');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
