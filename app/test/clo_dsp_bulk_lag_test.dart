// The web port's DI->response latency estimator must agree with the native one
// (`bulk_lag` in rust/src/api/generator.rs, test
// `bulk_lag_finds_a_latent_capture_and_ignores_an_aligned_one`). The Dart<->Rust
// golden is a well-aligned capture, which the gate leaves unshifted, so this is
// what covers the compensation path on the browser side — without it, a latent
// capture could be fixed natively and still import silent on web.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/clo_dsp.dart';

const _n = 300000;

/// Deterministic broadband excitation (xorshift64, same recurrence and seed as
/// the Rust test, so both run on the same signal).
Float64List _excitation() {
  final out = Float64List(_n);
  final scale = math.pow(2, 53).toDouble();
  var state = 0x243f6a8885a308d3;

  for (var i = 0; i < _n; i++) {
    state ^= state << 13;
    state ^= state >>> 7;
    state ^= state << 17;
    out[i] = (state >>> 11).toDouble() / scale * 2.0 - 1.0;
  }

  return out;
}

void main() {
  final di = _excitation();

  // a cab-ish response, so the correlation peak is broad rather than a spike
  final cab = Float64List(64);

  for (var i = 0; i < 64; i++) {
    cab[i] = math.exp(-i / 12.0) * (i % 7 < 4 ? 1.0 : -0.6);
  }

  final voiced = Float64List(_n);

  for (var k = 0; k < cab.length; k++) {
    for (var t = k; t < _n; t++) {
      voiced[t] += cab[k] * di[t - k];
    }
  }

  Float64List delayed(int d) {
    final out = Float64List(_n);

    out.setRange(d, _n, voiced);

    return out;
  }

  test('finds a latent capture\'s baked-in latency', () {
    for (final d in <int>[1781, 1193]) {
      final resp = delayed(d);
      final got = bulkLagOf(di, <Float64List>[resp, resp, resp, resp]);

      expect(
        (got - d).abs(),
        lessThanOrEqualTo(2),
        reason: 'latent capture lag $d misread as $got',
      );
    }
  });

  test('leaves a well-aligned capture unshifted', () {
    for (final d in <int>[0, 6, 16, 17, 64]) {
      final resp = delayed(d);

      expect(
        bulkLagOf(di, <Float64List>[resp, resp, resp, resp]),
        0,
        reason: 'aligned capture (lag $d) should not be shifted',
      );
    }
  });

  test('a flat vote leaves the fit where it is', () {
    expect(bulkLagOf(di, <Float64List>[Float64List(_n)]), 0);
    expect(bulkLagOf(di, <Float64List>[]), 0);
  });
}
