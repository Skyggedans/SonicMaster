// Pure-Dart port of `rust/src/api/generator.rs::generate_clo_arrays`.
//
// Flutter Web has no flutter_rust_bridge WASM path, so this reimplements the
// native `.nam` -> `.clo` converter in pure Dart: the classic/`v0.7.0` WaveNet
// parser + inference, sinc resampling, a self-contained radix-2 FFT (the `.nam`
// FFT sizes are all a power of two, so no Bluestein is needed), the Welch-Wiener
// FIR design, min-phase cepstral filter design, and the multi-level
// Wiener-Hammerstein fit. It is numerically faithful to the Rust (verified
// element-wise against a golden captured from the native path).
//
// f64 (`double`) is used throughout, matching the Rust; `f32` rounding is applied
// only at the input DI boundary and the final array outputs, exactly as Rust does.
//
// The DSP kernels below keep imperative index loops on purpose (dart-style rule
// 13 explicitly allows this for numeric fidelity/perf): the loop order and
// accumulation associativity mirror the Rust so the ported result tracks bit-for-
// bit within tolerance.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// The clone model's FIR arrays + nonlinearity gains, ready for the `.clo`.
///
/// Field-compatible with the flutter_rust_bridge `CloArrays` (arrayA/arrayB are
/// `Float32List`, gains is a `List<double>`) so the web path is a drop-in for the
/// native one without importing the FRB-generated bindings.
class CloArrays {
  const CloArrays({
    required this.arrayA,
    required this.arrayB,
    required this.gains,
  });

  final Float32List arrayA; // 128-tap pre-filter (input EQ)
  final Float32List arrayB; // 2048-tap post-filter (amp + cab)
  final List<double> gains; // [posmax, negmax, pos_rate, neg_rate]
}

const int _arrayALen = 128;
const int _arrayBLen = 2048;
const int _srcRate = 48000; // NAM inference rate
const int _deviceRate = 44100; // pedal rate the .clo stores

/// DI attenuations the amp model is probed at for the multi-level fit.
const List<double> _fitLevels = <double>[0.1, 0.03, 0.01, 0.003];

/// Extra "loud" probe level used only for pre-filter initialization.
const double _loudLevel = 1.0;

/// The full, ordered list of probe levels the WaveNet is run at: the multi-level
/// fit levels followed by the loud pre-filter level. Exposed so a parallel driver
/// can fan these out across workers (one [runOneProbeLevel] each) and reassemble
/// the result via [finishFromProbeResponses].
const List<double> cloProbeLevels = <double>[..._fitLevels, _loudLevel];

const int _fitStart = 300000;
const int _fitEnd = 1500000;
const int _runLen = 1600000;

const int _nfft = 8192;
const int _bins = _nfft ~/ 2 + 1;
const int _welchHop = _nfft ~/ 4;

// ---------------------------------------------------------------------------
// Public entry
// ---------------------------------------------------------------------------

/// Generates the clone-model arrays from a `.nam` (JSON) and the fixed reference
/// DI (mono, 44.1 kHz). Pure Dart analog of the native `generateCloArrays`.
///
/// Defined purely as the composition of the two split primitives — one
/// [runOneProbeLevel] per level in [cloProbeLevels], then a single
/// [finishFromProbeResponses] — so the sequential reference here and the parallel
/// (per-worker) driver share one source of truth and stay bit-for-bit identical.
CloArrays generateCloArraysDart(String namJson, List<double> referenceDi44100) {
  final responses = cloProbeLevels
      .map(
        (level) => (level, runOneProbeLevel(namJson, referenceDi44100, level)),
      )
      .toList();

  return finishFromProbeResponses(namJson, referenceDi44100, responses);
}

/// Parses the WaveNet model, resamples the reference DI to 48 kHz, scales it by
/// [level], and runs the WaveNet over it — the self-contained unit of work for
/// ONE probe level. Bit-identical to the entry the old sequential probe pass
/// produced for the same level, so a worker can run it off-thread with just
/// `{namJson, di, level}` and the reassembled result matches the reference.
Float64List runOneProbeLevel(
  String namJson,
  List<double> referenceDi44100,
  double level,
) {
  final (las, headScale) = _parseModel(namJson);
  final di48 = _resampleDiTo48(referenceDi44100);

  final scaled = Float64List(di48.length);

  for (var i = 0; i < di48.length; i++) {
    scaled[i] = di48[i] * level;
  }

  return _runWavenet(scaled, las, headScale);
}

/// Runs everything after the probe passes — the multi-level Wiener-Hammerstein
/// fit, the resample back to 48 kHz, and the final array/gain assembly — from the
/// per-level `(level, response)` pairs, producing the SAME [CloArrays] as the
/// all-in-one path. [namJson] is accepted for signature symmetry with
/// [runOneProbeLevel]; the fit itself needs only the DI and the responses.
CloArrays finishFromProbeResponses(
  String namJson,
  List<double> referenceDi44100,
  List<(double, Float64List)> responses,
) {
  final di48 = _resampleDiTo48(referenceDi44100);

  final (a48, b48, gains) = _fitWhMultilevel(di48, responses);

  final firA = _resample(a48, _deviceRate, _srcRate);
  final firB = _resample(b48, _deviceRate, _srcRate);

  final arrayA = Float32List(_arrayALen);

  for (var i = 0; i < _arrayALen && i < firA.length; i++) {
    arrayA[i] = firA[i];
  }

  final arrayB = Float32List(_arrayBLen);

  for (var i = 0; i < _arrayBLen && i < firB.length; i++) {
    arrayB[i] = firB[i];
  }

  // f32-round the gains to match the native `Vec<f32>` output.
  final gainsF32 = Float32List.fromList(<double>[
    gains.posmax,
    gains.negmax,
    gains.posRate,
    gains.negRate,
  ]);

  return CloArrays(arrayA: arrayA, arrayB: arrayB, gains: gainsF32.toList());
}

/// Parses the `.nam` JSON into the effective WaveNet (unwrapping any
/// `SlimmableContainer`) and its `head_scale`. Shared by [runOneProbeLevel] so
/// each worker rebuilds the model from just the JSON.
(List<_LayerArray>, double) _parseModel(String namJson) {
  final root = jsonDecode(namJson) as Map<String, dynamic>;
  final (config, weights) = _effectiveModel(root);

  return _parseWavenet(config, weights);
}

/// Resamples the reference DI (f32 @ 44.1 kHz) to f64 @ 48 kHz, capped at
/// [_runLen]. Deterministic and pure, so every caller (each probe worker and the
/// finishing fit) reconstructs a bit-identical `di48`.
Float64List _resampleDiTo48(List<double> referenceDi44100) {
  // DI arrives as f32 values; keep them as f64 (matches `v as f64` in Rust).
  final di44 = Float64List(referenceDi44100.length);

  for (var i = 0; i < di44.length; i++) {
    di44[i] = referenceDi44100[i];
  }

  // The fit only reads [0, RUN_LEN); cap the resample there (identical to the
  // Rust computing the full length then `truncate(RUN_LEN)`).
  return _resample(di44, _srcRate, _deviceRate, maxOut: _runLen);
}

// ---------------------------------------------------------------------------
// .nam parsing (classic WaveNet + v0.7.0 / SlimmableContainer)
// ---------------------------------------------------------------------------

enum _ActKind { tanh, leakyRelu }

class _Act {
  const _Act(this.kind, this.slope);

  final _ActKind kind;
  final double slope;
}

class _Layer {
  const _Layer({
    required this.convW,
    required this.convB,
    required this.mixinW,
    required this.outW,
    required this.outB,
    required this.dil,
    required this.act,
  });

  final List<List<Float64List>> convW; // per tap: [cout][cin]
  final Float64List convB;
  final List<Float64List> mixinW; // [channels][condition]
  final List<Float64List> outW; // [channels][channels]
  final Float64List outB;
  final int dil;
  final _Act act;
}

class _LayerArray {
  const _LayerArray({
    required this.rechW,
    required this.layers,
    required this.hrW,
    required this.hrB,
    required this.channels,
  });

  final List<Float64List> rechW; // [channels][input]
  final List<_Layer> layers;
  final List<List<Float64List>>
  hrW; // head_rechannel conv1d: per tap [head_out][channels]
  final Float64List hrB;
  final int channels;
}

class _Cursor {
  _Cursor(this.w);

  final List<double> w;
  int pos = 0;

  Float64List take(int n) {
    final s = Float64List(n);

    for (var i = 0; i < n; i++) {
      s[i] = w[pos + i];
    }

    pos += n;

    return s;
  }

  /// Conv1d weights: PyTorch flatten [out][in][k] then bias[out].
  (List<List<Float64List>>, Float64List) conv1d(
    int cin,
    int cout,
    int ks,
    bool bias,
  ) {
    final raw = take(cout * cin * ks);

    final kernels = List.generate(
      ks,
      (k) => List.generate(cout, (o) {
        final row = Float64List(cin);

        for (var i = 0; i < cin; i++) {
          row[i] = raw[(o * cin + i) * ks + k];
        }

        return row;
      }),
    );

    final b = bias ? take(cout) : Float64List(cout);

    return (kernels, b);
  }

  /// Conv1x1 = Conv1d with kernel 1: row-major (out,in) then bias[out].
  (List<Float64List>, Float64List?) conv1x1(int cin, int cout, bool bias) {
    final raw = take(cout * cin);

    final m = List.generate(cout, (o) {
      final row = Float64List(cin);

      for (var i = 0; i < cin; i++) {
        row[i] = raw[o * cin + i];
      }

      return row;
    });

    final b = bias ? take(cout) : null;

    return (m, b);
  }
}

int _ju(Map<String, dynamic> v, String key) => (v[key] as num).toInt();

bool _featureActive(dynamic v) {
  if (v is Map) {
    return v['active'] == true;
  }

  if (v == null) {
    return false;
  }

  return true;
}

void _assertLayerSupported(Map<String, dynamic> la) {
  final gatingMode = la['gating_mode'];
  final gated =
      (la['gated'] == true) ||
      (gatingMode is List && gatingMode.any((v) => v != 'none'));

  if (gated) {
    throw StateError('gated WaveNet not supported');
  }

  final bottleneck = la['bottleneck'];

  if (bottleneck is num && bottleneck.toInt() != _ju(la, 'channels')) {
    throw StateError('WaveNet bottleneck not supported');
  }

  if (_featureActive(la['head1x1']) || _featureActive(la['head_1x1_config'])) {
    throw StateError('WaveNet head 1x1 not supported');
  }

  const film = <String>[
    'conv_pre_film',
    'conv_post_film',
    'input_mixin_pre_film',
    'input_mixin_post_film',
    'activation_pre_film',
    'activation_post_film',
    'layer1x1_post_film',
    'head1x1_post_film',
    'film_params',
  ];

  if (film.any((k) => _featureActive(la[k]))) {
    throw StateError('WaveNet FiLM not supported');
  }
}

_Act _parseAct(dynamic v) {
  final String name;

  if (v is String) {
    name = v;
  } else if (v is Map) {
    name = (v['type'] as String?) ?? 'Tanh';
  } else {
    name = 'Tanh';
  }

  switch (name) {
    case 'Tanh':
      return const _Act(.tanh, 0.0);
    case 'LeakyReLU':
      final slope =
          (v is Map ? (v['negative_slope'] as num?)?.toDouble() : null) ?? 0.01;

      return _Act(.leakyRelu, slope);
    case 'ReLU':
      return const _Act(.leakyRelu, 0.0);
    default:
      throw StateError('unsupported activation `$name`');
  }
}

List<_Act> _layerActs(Map<String, dynamic> cfg, int n) {
  final a = cfg['activation'];

  if (a is List) {
    return a.map(_parseAct).toList();
  }

  if (a != null) {
    return List.filled(n, _parseAct(a));
  }

  return List.filled(n, const _Act(.tanh, 0.0));
}

/// Unwrap a `SlimmableContainer` to its highest-quality (max `max_value`)
/// submodel; a plain WaveNet passes through. Returns (config, weights).
(Map<String, dynamic>, List<double>) _effectiveModel(
  Map<String, dynamic> root,
) {
  if (root['architecture'] == 'SlimmableContainer') {
    final subs = (root['config'] as Map)['submodels'] as List;

    var best = subs.first as Map;
    var bestVal = (best['max_value'] as num?)?.toDouble() ?? 0.0;

    for (final s in subs) {
      final m = s as Map;
      final v = (m['max_value'] as num?)?.toDouble() ?? 0.0;

      // `max_by` returns the last of equal maxima -> use `>=`.
      if (v >= bestVal) {
        best = m;
        bestVal = v;
      }
    }

    return _effectiveModel(best['model'] as Map<String, dynamic>);
  }

  final rawWeights = root['weights'] as List;
  final weights = List<double>.generate(
    rawWeights.length,
    (i) => (rawWeights[i] as num).toDouble(),
  );

  return (root['config'] as Map<String, dynamic>, weights);
}

(List<_LayerArray>, double) _parseWavenet(
  Map<String, dynamic> config,
  List<double> weights,
) {
  final cur = _Cursor(weights);
  final headScale = (config['head_scale'] as num?)?.toDouble() ?? 1.0;
  final layersCfg = config['layers'] as List;

  final layerArrays = layersCfg.map((raw) {
    final la = raw as Map<String, dynamic>;

    _assertLayerSupported(la);

    final inputSize = _ju(la, 'input_size');
    final conditionSize = _ju(la, 'condition_size');
    final channels = _ju(la, 'channels');
    final dilations = (la['dilations'] as List)
        .map((e) => (e as num).toInt())
        .toList();

    final kernels = la['kernel_sizes'] != null
        ? (la['kernel_sizes'] as List).map((e) => (e as num).toInt()).toList()
        : List.filled(dilations.length, _ju(la, 'kernel_size'));

    final int headOut;
    final int headKs;
    final bool headBias;
    final headCfg = la['head'];

    if (headCfg is Map) {
      headOut = _ju(headCfg.cast<String, dynamic>(), 'out_channels');
      headKs = _ju(headCfg.cast<String, dynamic>(), 'kernel_size');
      headBias = (headCfg['bias'] as bool?) ?? true;
    } else {
      headOut = _ju(la, 'head_size');
      headKs = 1;
      headBias = (la['head_bias'] as bool?) ?? false;
    }

    final acts = _layerActs(la, dilations.length);

    final (rechW, _) = cur.conv1x1(inputSize, channels, false);

    final layers = List.generate(dilations.length, (li) {
      final (cw, cb) = cur.conv1d(channels, channels, kernels[li], true);
      final (mw, _) = cur.conv1x1(conditionSize, channels, false);
      final (ow, ob) = cur.conv1x1(channels, channels, true);

      return _Layer(
        convW: cw,
        convB: cb,
        mixinW: mw,
        outW: ow,
        outB: ob!,
        dil: dilations[li],
        act: acts[li],
      );
    });

    final (hrW, hrB) = cur.conv1d(channels, headOut, headKs, headBias);

    return _LayerArray(
      rechW: rechW,
      layers: layers,
      hrW: hrW,
      hrB: hrB,
      channels: channels,
    );
  }).toList();

  return (layerArrays, headScale);
}

// ---------------------------------------------------------------------------
// WaveNet forward pass
// ---------------------------------------------------------------------------

/// `out[r][j] = sum_i m[r][i] * x[i][j]`. Writes into the caller-provided [out]
/// (each row zeroed first), so a single `rows x T` scratch can be reused across
/// layers and probe levels instead of allocating a fresh buffer per call. The
/// accumulation order is identical to the old fresh-allocating `_matmul`, so the
/// result is bit-for-bit unchanged.
void _matmulInto(
  List<Float64List> m,
  List<Float64List> x,
  List<Float64List> out,
) {
  final t = x[0].length;
  final rows = m.length;
  final kk = m[0].length;

  for (var r = 0; r < rows; r++) {
    final mr = m[r];
    final outr = out[r];

    outr.fillRange(0, t, 0.0);

    for (var i = 0; i < kk; i++) {
      final w = mr[i];
      final xi = x[i];

      for (var j = 0; j < t; j++) {
        outr[j] += w * xi[j];
      }
    }
  }
}

/// Dilated conv1d into the caller-provided [out] (`cout x T`, zeroed first). Same
/// bit-exact accumulation as the old fresh-allocating `_conv1dApply`; the buffer
/// is passed in so it can be reused across the (many) dilated layers.
void _conv1dApplyInto(
  List<Float64List> x,
  List<List<Float64List>> kernels,
  Float64List b,
  int dil,
  List<Float64List> out,
) {
  final cout = kernels[0].length;
  final t = x[0].length;
  final k = kernels.length;
  final cin = x.length;

  for (var o = 0; o < cout; o++) {
    out[o].fillRange(0, t, 0.0);
  }

  for (var ki = 0; ki < k; ki++) {
    final kernel = kernels[ki];
    final shift = dil * (k - 1 - ki); // = -offset, >= 0

    for (var o = 0; o < cout; o++) {
      final kro = kernel[o];
      final outo = out[o];

      for (var tt = shift; tt < t; tt++) {
        final src = tt - shift;
        var acc = 0.0;

        for (var i = 0; i < cin; i++) {
          acc += kro[i] * x[i][src];
        }

        outo[tt] += acc;
      }
    }
  }

  for (var o = 0; o < cout; o++) {
    final outo = out[o];
    final bo = b[o];

    for (var tt = 0; tt < t; tt++) {
      outo[tt] += bo;
    }
  }
}

double _activate(_Act act, double v) {
  switch (act.kind) {
    case _ActKind.tanh:
      return _tanh(v);
    case _ActKind.leakyRelu:
      return v >= 0.0 ? v : act.slope * v;
  }
}

double _tanh(double x) {
  if (x > 20.0) {
    return 1.0;
  }

  if (x < -20.0) {
    return -1.0;
  }

  final e2 = math.exp(2.0 * x);

  return (e2 - 1.0) / (e2 + 1.0);
}

Float64List _runWavenet(
  Float64List mono,
  List<_LayerArray> las,
  double headScale,
) {
  final t = mono.length;
  final cond = <Float64List>[mono]; // read-only conditioning

  var head = <Float64List>[];
  var x = <Float64List>[mono];

  for (final la in las) {
    final ch = la.channels;

    // Per-layer-array buffers: `xx` becomes the next array's input; `acc`
    // accumulates the head branch. Allocated once per array (not per dilated
    // layer) so the 20-plus dilated layers reuse the scratch below.
    final xx = List.generate(ch, (_) => Float64List(t));

    _matmulInto(la.rechW, x, xx);

    final acc = List.generate(ch, (_) => Float64List(t));

    for (var i = 0; i < head.length && i < acc.length; i++) {
      final ai = acc[i];
      final hi = head[i];

      for (var j = 0; j < t; j++) {
        ai[j] += hi[j];
      }
    }

    // Scratch reused across every dilated layer in this array: `_conv1dApplyInto`
    // and `_matmulInto` zero their output first, and `post` is fully overwritten
    // each layer, so no stale values leak between iterations.
    final conv = List.generate(ch, (_) => Float64List(t));
    final mixin = List.generate(ch, (_) => Float64List(t));
    final post = List.generate(ch, (_) => Float64List(t));
    final ow = List.generate(ch, (_) => Float64List(t));

    for (final layer in la.layers) {
      _conv1dApplyInto(xx, layer.convW, layer.convB, layer.dil, conv);
      _matmulInto(layer.mixinW, cond, mixin);

      for (var c = 0; c < ch; c++) {
        final cc = conv[c];
        final mm = mixin[c];
        final pc = post[c];

        for (var j = 0; j < t; j++) {
          pc[j] = _activate(layer.act, cc[j] + mm[j]);
        }
      }

      for (var c = 0; c < ch; c++) {
        final ac = acc[c];
        final pc = post[c];

        for (var j = 0; j < t; j++) {
          ac[j] += pc[j];
        }
      }

      _matmulInto(layer.outW, post, ow);

      for (var c = 0; c < ch; c++) {
        final xc = xx[c];
        final oc = ow[c];
        final bc = layer.outB[c];

        for (var j = 0; j < t; j++) {
          xc[j] += oc[j] + bc;
        }
      }
    }

    final headRows = la.hrW[0].length;
    final headOut = List.generate(headRows, (_) => Float64List(t));

    _conv1dApplyInto(acc, la.hrW, la.hrB, 1, headOut);

    x = xx;
    head = headOut;
  }

  final h0 = head[0];
  final out = Float64List(t);

  for (var j = 0; j < t; j++) {
    out[j] = headScale * h0[j];
  }

  return out;
}

// ---------------------------------------------------------------------------
// Sinc resampling
// ---------------------------------------------------------------------------

double _sinc(double x) {
  if (x.abs() < 1e-9) {
    return 1.0;
  }

  final p = math.pi * x;

  return math.sin(p) / p;
}

double _blackman(double d, double half) {
  if (d.abs() > half) {
    return 0.0;
  }

  final n = (d + half) / (2.0 * half);

  return 0.42 -
      0.5 * math.cos(2.0 * math.pi * n) +
      0.08 * math.cos(4.0 * math.pi * n);
}

/// Windowed-sinc arbitrary-ratio resample. [maxOut], when given, caps the number
/// of output samples produced (the leading outputs are identical to the full
/// resample, so this matches Rust's "resample then `truncate`").
Float64List _resample(Float64List x, int up, int down, {int? maxOut}) {
  final ratio = up / down;
  final natural = (x.length * ratio).floor();
  final outLen = maxOut != null ? math.min(natural, maxOut) : natural;
  const half = 16;
  final cutoff = math.min(up, down) / math.max(up, down);

  final out = Float64List(outLen);

  for (var kk = 0; kk < outLen; kk++) {
    final center = kk / ratio;
    final i0 = center.floor();
    var acc = 0.0;

    for (var j = i0 - half; j <= i0 + half; j++) {
      if (j < 0 || j >= x.length) {
        continue;
      }

      final d = center - j;
      final w = cutoff * _sinc(cutoff * d) * _blackman(d, half.toDouble());

      acc += x[j] * w;
    }

    out[kk] = acc;
  }

  return out;
}

// ---------------------------------------------------------------------------
// Self-contained radix-2 FFT (all .nam FFT sizes are a power of two)
// ---------------------------------------------------------------------------

class _Fft {
  _Fft(this.n)
    : _rev = Int32List(n),
      _cos = Float64List(n ~/ 2),
      _sin = Float64List(n ~/ 2) {
    var bits = 0;

    while ((1 << bits) < n) {
      bits++;
    }

    for (var i = 0; i < n; i++) {
      var r = 0;

      for (var b = 0; b < bits; b++) {
        if ((i & (1 << b)) != 0) {
          r |= 1 << (bits - 1 - b);
        }
      }

      _rev[i] = r;
    }

    for (var i = 0; i < n ~/ 2; i++) {
      final angle = 2.0 * math.pi * i / n;

      _cos[i] = math.cos(angle);
      _sin[i] = math.sin(angle);
    }
  }

  final int n;
  final Int32List _rev;
  final Float64List _cos;
  final Float64List _sin;

  /// In-place complex FFT. Forward uses e^{-i.}, inverse e^{+i.}; both are
  /// UNNORMALIZED (matches rustfft/realfft — callers divide by N by hand).
  void transform(Float64List re, Float64List im, bool inverse) {
    for (var i = 0; i < n; i++) {
      final j = _rev[i];

      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;

        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }

    for (var len = 2; len <= n; len <<= 1) {
      final half = len >> 1;
      final step = n ~/ len;

      for (var i = 0; i < n; i += len) {
        for (var j = 0; j < half; j++) {
          final m = j * step;
          final wr = _cos[m];
          final wi = inverse ? _sin[m] : -_sin[m];
          final a = i + j;
          final b = a + half;
          final tr = wr * re[b] - wi * im[b];
          final ti = wr * im[b] + wi * re[b];

          re[b] = re[a] - tr;
          im[b] = im[a] - ti;
          re[a] += tr;
          im[a] += ti;
        }
      }
    }
  }
}

_Fft? _fftCache;

_Fft get _fft => _fftCache ??= _Fft(_nfft);

/// Real FFT (forward): fills [outRe]/[outIm] (length BINS) with the first N/2+1
/// bins of the full complex DFT of the real [signal] (length N). Uses scratch
/// buffers [scrRe]/[scrIm] (length N) to avoid per-call allocation.
void _rfftForwardInto(
  Float64List signal,
  Float64List scrRe,
  Float64List scrIm,
  Float64List outRe,
  Float64List outIm,
) {
  for (var i = 0; i < _nfft; i++) {
    scrRe[i] = signal[i];
    scrIm[i] = 0.0;
  }

  _fft.transform(scrRe, scrIm, false);

  for (var i = 0; i < _bins; i++) {
    outRe[i] = scrRe[i];
    outIm[i] = scrIm[i];
  }
}

/// Real inverse FFT: reconstructs the Hermitian-symmetric full spectrum from the
/// N/2+1 bins ([re]/[im]) and inverse-transforms it. Returns the N real samples,
/// UNNORMALIZED (caller divides by N). DC/Nyquist are real in every use here, so
/// the real part matches realfft's `ComplexToReal` output exactly.
Float64List _irfft(Float64List re, Float64List im) {
  final fr = Float64List(_nfft);
  final fi = Float64List(_nfft);

  for (var k = 0; k < _bins; k++) {
    fr[k] = re[k];
    fi[k] = im[k];
  }

  for (var k = 1; k < _nfft ~/ 2; k++) {
    fr[_nfft - k] = re[k];
    fi[_nfft - k] = -im[k];
  }

  _fft.transform(fr, fi, true);

  return fr;
}

// ---------------------------------------------------------------------------
// Welch-averaged Wiener FIR + min-phase design
// ---------------------------------------------------------------------------

Float64List _hann() {
  final w = Float64List(_nfft);

  for (var i = 0; i < _nfft; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2.0 * math.pi * i / _nfft);
  }

  return w;
}

class _Spec {
  const _Spec(this.re, this.im);

  final Float64List re;
  final Float64List im;
}

/// Welch-averaged cross/auto spectra over several (x, y) pairs:
/// `H = sum(Y * conj(X)) / (sum(|X|^2) + reg)`.
_Spec _welchPairs(List<(Float64List, Float64List)> pairs, double reg) {
  final win = _hann();
  final xr = Float64List(_nfft);
  final xi = Float64List(_nfft);
  final yr = Float64List(_nfft);
  final yi = Float64List(_nfft);

  final sxyRe = Float64List(_bins);
  final sxyIm = Float64List(_bins);
  final sxx = Float64List(_bins);

  for (final (x, y) in pairs) {
    final lim = math.min(x.length, y.length);
    var start = 0;

    while (start + _nfft <= lim) {
      for (var i = 0; i < _nfft; i++) {
        xr[i] = x[start + i] * win[i];
        xi[i] = 0.0;
        yr[i] = y[start + i] * win[i];
        yi[i] = 0.0;
      }

      _fft.transform(xr, xi, false);
      _fft.transform(yr, yi, false);

      for (var i = 0; i < _bins; i++) {
        final axr = xr[i];
        final axi = xi[i];
        final ayr = yr[i];
        final ayi = yi[i];

        // Y * conj(X)
        sxyRe[i] += ayr * axr + ayi * axi;
        sxyIm[i] += ayi * axr - ayr * axi;
        sxx[i] += axr * axr + axi * axi;
      }

      start += _welchHop;
    }
  }

  var sxxMax = 0.0;

  for (var i = 0; i < _bins; i++) {
    if (sxx[i] > sxxMax) {
      sxxMax = sxx[i];
    }
  }

  final eps = reg * sxxMax;
  final hRe = Float64List(_bins);
  final hIm = Float64List(_bins);

  for (var i = 0; i < _bins; i++) {
    final den = sxx[i] + eps;

    hRe[i] = sxyRe[i] / den;
    hIm[i] = sxyIm[i] / den;
  }

  return _Spec(hRe, hIm);
}

/// First [nTaps] of the impulse response of spectrum [h].
Float64List _firify(_Spec h, int nTaps) {
  final ir = _irfft(h.re, h.im);
  final out = Float64List(nTaps);

  for (var i = 0; i < nTaps; i++) {
    out[i] = ir[i] / _nfft;
  }

  return out;
}

/// Min-phase FIR ([nTaps]) whose magnitude response matches [mag] (real cepstrum
/// method: log-magnitude -> causal cepstral window -> exp).
Float64List _minphaseMag(Float64List mag, int nTaps) {
  final re = Float64List(_nfft);
  final im = Float64List(_nfft);

  for (var i = 0; i < _nfft; i++) {
    final bin = i < _bins ? i : _nfft - i;

    re[i] = math.log(math.max(mag[bin], 1e-9));
    im[i] = 0.0;
  }

  _fft.transform(re, im, true); // cepstrum (unnormalized)

  for (var i = 0; i < _nfft; i++) {
    final double w;

    if (i == 0 || i == _nfft ~/ 2) {
      w = 1.0;
    } else if (i < _nfft ~/ 2) {
      w = 2.0;
    } else {
      w = 0.0;
    }

    re[i] = re[i] / _nfft * w;
    im[i] = 0.0;
  }

  _fft.transform(re, im, false);

  for (var i = 0; i < _nfft; i++) {
    final ex = math.exp(re[i]);

    re[i] = ex * math.cos(im[i]);
    im[i] = ex * math.sin(im[i]);
  }

  _fft.transform(re, im, true);

  final out = Float64List(nTaps);

  for (var i = 0; i < nTaps; i++) {
    out[i] = re[i] / _nfft;
  }

  return out;
}

const double _pow2Neg = 0.9438743126816935; // 2^(-0.5/6)
const double _pow2Pos = 1.0594630943592953; // 2^(0.5/6)

/// Smooths a magnitude spectrum over ~1/6 octave (log-frequency).
Float64List _logsmooth(Float64List mag) {
  final out = Float64List(_bins);

  out[0] = mag[0];

  for (var i = 1; i < _bins; i++) {
    final f = i.toDouble();
    final rawLo = (f * _pow2Neg).toInt();
    final hi = math.min((f * _pow2Pos).toInt() + 1, _bins);
    final lo = math.min(math.max(rawLo, 1), hi - 1);

    var sum = 0.0;

    for (var j = lo; j < hi; j++) {
      sum += mag[j];
    }

    out[i] = sum / (hi - lo);
  }

  return out;
}

/// Regularized frequency-domain deconvolution of [y] by FIR [b] (overlap-add,
/// Hann analysis+synthesis).
Float64List _deconv(Float64List y, Float64List b, double reg) {
  final win = _hann();

  final bbuf = Float64List(_nfft);

  for (var i = 0; i < b.length && i < _nfft; i++) {
    bbuf[i] = b[i];
  }

  final scrRe = Float64List(_nfft);
  final scrIm = Float64List(_nfft);
  final hbRe = Float64List(_bins);
  final hbIm = Float64List(_bins);

  _rfftForwardInto(bbuf, scrRe, scrIm, hbRe, hbIm);

  var hmax = 0.0;

  for (var i = 0; i < _bins; i++) {
    final ns = hbRe[i] * hbRe[i] + hbIm[i] * hbIm[i];

    if (ns > hmax) {
      hmax = ns;
    }
  }

  final invRe = Float64List(_bins);
  final invIm = Float64List(_bins);

  for (var i = 0; i < _bins; i++) {
    final den = hbRe[i] * hbRe[i] + hbIm[i] * hbIm[i] + reg * hmax;

    invRe[i] = hbRe[i] / den;
    invIm[i] = -hbIm[i] / den;
  }

  final out = Float64List(y.length);
  final norm = Float64List(y.length);
  final yr = Float64List(_nfft);
  final yi = Float64List(_nfft);
  var start = 0;

  while (start + _nfft <= y.length) {
    for (var i = 0; i < _nfft; i++) {
      yr[i] = y[start + i] * win[i];
      yi[i] = 0.0;
    }

    _fft.transform(yr, yi, false);

    // Multiply the N/2+1 unique bins by the inverse filter, then restore the
    // Hermitian upper half before the inverse transform.
    for (var i = 0; i < _bins; i++) {
      final ar = yr[i];
      final ai = yi[i];

      yr[i] = ar * invRe[i] - ai * invIm[i];
      yi[i] = ar * invIm[i] + ai * invRe[i];
    }

    for (var k = 1; k < _nfft ~/ 2; k++) {
      yr[_nfft - k] = yr[k];
      yi[_nfft - k] = -yi[k];
    }

    _fft.transform(yr, yi, true);

    for (var i = 0; i < _nfft; i++) {
      out[start + i] += yr[i] / _nfft * win[i];
      norm[start + i] += win[i] * win[i];
    }

    start += _welchHop;
  }

  for (var i = 0; i < out.length; i++) {
    out[i] /= math.max(norm[i], 1e-3);
  }

  return out;
}

// ---------------------------------------------------------------------------
// Nonlinearity + multi-level Wiener-Hammerstein fit
// ---------------------------------------------------------------------------

class _Gains {
  const _Gains(this.posmax, this.negmax, this.posRate, this.negRate);

  final double posmax;
  final double negmax;
  final double posRate;
  final double negRate;
}

/// The pedal's asymmetric exponential saturator.
Float64List _nlFwd(Float64List v, _Gains g) {
  final out = Float64List(v.length);

  for (var i = 0; i < v.length; i++) {
    final x = v[i];

    if (x > 0.0) {
      out[i] = g.posmax * (1.0 - math.exp(math.max(-g.posRate * x, -60.0)));
    } else {
      out[i] = -g.negmax * (1.0 - math.exp(math.min(g.negRate * x, 60.0)));
    }
  }

  return out;
}

/// Fits the saturator to per-level (pre-drive -> target output) pairs.
_Gains _fitNl(List<Float64List> vs, List<Float64List> ts) {
  const stride = 16;

  final vq = vs.last;
  final mags = <double>[];

  for (var i = 0; i < vq.length; i += stride) {
    final a = vq[i].abs();

    if (a > 1e-8) {
      mags.add(a);
    }
  }

  mags.sort();

  final idx = (mags.length * 9) ~/ 10;
  final p90 = idx < mags.length ? mags[idx] : 1e-3;
  final rMax = math.max(1.0 / math.max(p90, 1e-9), 1.0);
  const rMin = 0.5;

  (double, double) fitSide(double sign) {
    // per level: (v samples, t samples, weight)
    final xsl = <Float64List>[];
    final ysl = <Float64List>[];
    final wl = <double>[];

    for (var li = 0; li < vs.length; li++) {
      final v = vs[li];
      final t = ts[li];
      final lim = math.min(v.length, t.length);
      final xs = <double>[];
      final ys = <double>[];

      for (var i = 0; i < lim; i += stride) {
        final x = v[i] * sign;

        if (x > 1e-8) {
          xs.add(x);
          ys.add(t[i] * sign);
        }
      }

      var sumsq = 0.0;

      for (final yv in ys) {
        sumsq += yv * yv;
      }

      final rms = math.sqrt(sumsq / math.max(ys.length, 1));

      xsl.add(Float64List.fromList(xs));
      ysl.add(Float64List.fromList(ys));
      wl.add(1.0 / math.max(rms, 1e-9));
    }

    var bestResid = double.infinity;
    var bestC = 1.0;
    var bestR = 1.0;
    const n = 80;

    for (var kk = 0; kk < n; kk++) {
      final r = rMin * math.pow(rMax / rMin, kk / (n - 1));

      var num = 0.0;
      var den = 0.0;

      for (var li = 0; li < xsl.length; li++) {
        final xs = xsl[li];
        final ys = ysl[li];
        final w = wl[li];

        for (var s = 0; s < xs.length; s++) {
          final e = 1.0 - math.exp(math.max(-r * xs[s], -60.0));

          num += w * ys[s] * e;
          den += w * e * e;
        }
      }

      if (den < 1e-12) {
        continue;
      }

      final c = num / den;

      if (c <= 0.0) {
        continue;
      }

      var resid = 0.0;

      for (var li = 0; li < xsl.length; li++) {
        final xs = xsl[li];
        final ys = ysl[li];
        final w = wl[li];
        var se = 0.0;

        for (var s = 0; s < xs.length; s++) {
          final e = 1.0 - math.exp(math.max(-r * xs[s], -60.0));
          final d = ys[s] - c * e;

          se += d * d;
        }

        resid += w * se / math.max(xs.length, 1);
      }

      if (resid < bestResid) {
        bestResid = resid;
        bestC = c;
        bestR = r;
      }
    }

    return (bestC, bestR);
  }

  final (posmax, posRate) = fitSide(1.0);
  final (negmax, negRate) = fitSide(-1.0);

  return _Gains(posmax, negmax, posRate, negRate);
}

/// Direct FIR convolution (kernel <= 128 taps).
Float64List _convFir(Float64List x, Float64List h) {
  final y = Float64List(x.length);

  for (var k = 0; k < h.length; k++) {
    final hk = h[k];

    if (hk == 0.0) {
      continue;
    }

    for (var t = k; t < x.length; t++) {
      y[t] += hk * x[t - k];
    }
  }

  return y;
}

/// The multi-level fit: probe responses come in as (level, response) pairs over
/// [0, RUN_LEN); returns (arrayA48[128], arrayB48[2048], gains).
(Float64List, Float64List, _Gains) _fitWhMultilevel(
  Float64List di48,
  List<(double, Float64List)> respByLevel,
) {
  Float64List seg(Float64List x) {
    final end = math.min(_fitEnd, x.length);

    return Float64List.sublistView(x, _fitStart, end);
  }

  Float64List respOf(double lvl) {
    for (final (l, r) in respByLevel) {
      if (l == lvl) {
        return r;
      }
    }

    throw StateError('probe level missing: $lvl');
  }

  Float64List scaledSeg(Float64List x, double k) {
    final s = seg(x);
    final out = Float64List(s.length);

    for (var i = 0; i < s.length; i++) {
      out[i] = s[i] * k;
    }

    return out;
  }

  final quiet = _fitLevels.last;
  final xsFit = _fitLevels.map((k) => scaledSeg(di48, k)).toList();
  final ysFit = _fitLevels.map((k) => seg(respOf(k))).toList();

  // arrayA init: min-phase of the smoothed two-level ratio, unity at ~1 kHz.
  final xQ = scaledSeg(di48, quiet);
  final xL = scaledSeg(di48, _loudLevel);
  final hQ = _welchPairs(<(Float64List, Float64List)>[
    (xQ, seg(respOf(quiet))),
  ], 1e-5);
  final hL = _welchPairs(<(Float64List, Float64List)>[
    (xL, seg(respOf(_loudLevel))),
  ], 1e-5);

  final ratioRaw = Float64List(_bins);

  for (var i = 0; i < _bins; i++) {
    final nq = math.sqrt(hQ.re[i] * hQ.re[i] + hQ.im[i] * hQ.im[i]);
    final nl = math.sqrt(hL.re[i] * hL.re[i] + hL.im[i] * hL.im[i]);

    ratioRaw[i] = nq / math.max(nl, 1e-9);
  }

  final ratio = _logsmooth(ratioRaw);
  final bin1k = 1000 * _nfft ~/ _srcRate;
  final norm = math.max(ratio[bin1k], 1e-9);

  for (var i = 0; i < _bins; i++) {
    ratio[i] /= norm;
  }

  final a48 = _minphaseMag(ratio, _arrayALen);

  // arrayB init: the hard-driven transfer.
  var b48 = _firify(hL, _arrayBLen);

  // Coordinate descent: NL from deconvolved targets, B from multi-level Welch.
  final vs = xsFit.map((x) => _convFir(x, a48)).toList();
  var gains = const _Gains(1.0, 1.0, 1.0, 1.0);

  for (var round = 0; round < 3; round++) {
    final ts = ysFit.map((y) => _deconv(y, b48, 3e-3)).toList();

    gains = _fitNl(vs, ts);

    final us = vs.map((v) => _nlFwd(v, gains)).toList();
    final pairs = List.generate(us.length, (i) => (us[i], ysFit[i]));

    b48 = _firify(_welchPairs(pairs, 1e-5), _arrayBLen);
  }

  return (a48, b48, gains);
}
