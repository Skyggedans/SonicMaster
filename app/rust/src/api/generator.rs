//! Native `.nam` → clone-model generator — the open-source analog of the
//! vendor DLL's `namConvertCloData`. Runs the classic NAM WaveNet over the fixed
//! reference DI, fits a Wiener-Hammerstein post-filter, and returns the pedal's
//! two FIR arrays + gains. Dart serializes these into a `.clo` (see
//! `clo_codec.dart`). Algorithm verified against the tool (see CLO_SPEC.md).

use realfft::RealFftPlanner;

const ARRAY_A_LEN: usize = 128;
const ARRAY_B_LEN: usize = 2048;
const SRC_RATE: usize = 48000; // NAM inference rate
const DEVICE_RATE: usize = 44100; // pedal rate the .clo stores

/// The DI attenuations the amp model is probed at for the multi-level fit. The
/// saturator's curvature is only identifiable ACROSS input levels (at any single
/// level an arbitrary NL is compensated by the post-filter — the bug that made
/// high-gain clones come out clean); these span the guitar playing range. The
/// bundled reference DI peaks at 1.0, far hotter than the pedal's input, so the
/// quiet levels are where the fit must hold. Verified against the vendor's own
/// .clo for the same amp (we match or beat its per-level corr and loudness).
const FIT_LEVELS: [f64; 4] = [0.1, 0.03, 0.01, 0.003];

/// Extra "loud" probe level used only for the pre-filter initialization: a hard-
/// driven pass flattens the pre-clip EQ, so |H_quiet|/|H_loud| exposes arrayA.
const LOUD_LEVEL: f64 = 1.0;

/// Welch/fit segment bounds at 48 kHz. Only [0, RUN_LEN) of each probe response
/// is needed (fit on FIT_*, headroom for the FFT hop), roughly halving the five
/// WaveNet passes vs running the full DI.
const FIT_START: usize = 300_000;
const FIT_END: usize = 1_500_000;
const RUN_LEN: usize = 1_600_000;

const NFFT: usize = 8192;

/// The clone model's FIR arrays + nonlinearity gains, ready for the `.clo`.
pub struct CloArrays {
    pub array_a: Vec<f32>, // 128-tap pre-filter (input EQ)
    pub array_b: Vec<f32>, // 2048-tap post-filter (amp + cab)
    pub gains: Vec<f32>,   // [POSMAX, NEGMAX, pos_rate, neg_rate]
}

// ---- .nam parsing (classic WaveNet + v0.7.0 / SlimmableContainer) ----
//
// Two on-disk WaveNet schemas are supported, unified onto one runtime model:
//   * classic   — per layer: `kernel_size` (int), `activation` ("Tanh"), `gated`,
//                 head_rechannel = Conv1x1 (`head_size` + `head_bias`).
//   * v0.7.0    — per layer: `kernel_sizes` (list), `activation` (list of
//                 {type, negative_slope}), head_rechannel = Conv1d
//                 (`head` = {out_channels, kernel_size, bias}). Tone3000 exports
//                 wrap several of these WaveNets in a `SlimmableContainer`; the
//                 highest-quality submodel (max `max_value`) is the clone source.
// Weight layout (verified byte-exact against the reference nam package): per layer
// array, rechannel → per layer [conv, input_mixer, layer1x1] → head_rechannel;
// then a trailing `head_scale` scalar. Conv weights are PyTorch-flattened
// [out][in][k] then bias.

use serde_json::Value;

type Mat = Vec<Vec<f64>>; // rows x cols

#[derive(Clone, Copy)]
enum Act {
    Tanh,
    LeakyRelu(f64),
}

struct Layer {
    conv_w: Vec<Mat>, // per-layer kernel matrices, each channels x channels
    conv_b: Vec<f64>,
    mixin_w: Mat, // channels x condition
    out_w: Mat,   // layer1x1: channels x channels
    out_b: Vec<f64>,
    dil: usize,
    act: Act,
}

struct LayerArray {
    rech_w: Mat, // channels x input
    layers: Vec<Layer>,
    hr_w: Vec<Mat>, // head_rechannel conv1d: head_out x channels, one Mat per tap
    hr_b: Vec<f64>, // head_out (zeros if no bias)
    channels: usize,
}

struct Cursor<'a> {
    w: &'a [f64],
    pos: usize,
}

impl<'a> Cursor<'a> {
    fn take(&mut self, n: usize) -> &'a [f64] {
        let s = &self.w[self.pos..self.pos + n];
        self.pos += n;

        s
    }

    /// Conv1d weights: PyTorch flatten [out][in][k] then bias[out].
    fn conv1d(&mut self, cin: usize, cout: usize, ks: usize, bias: bool) -> (Vec<Mat>, Vec<f64>) {
        let raw = self.take(cout * cin * ks).to_vec();
        let kernels: Vec<Mat> = (0..ks)
            .map(|k| {
                (0..cout)
                    .map(|o| (0..cin).map(|i| raw[(o * cin + i) * ks + k]).collect())
                    .collect()
            })
            .collect();
        let b = if bias { self.take(cout).to_vec() } else { vec![0.0; cout] };

        (kernels, b)
    }

    /// Conv1x1 = Conv1d with kernel 1: row-major (out,in) then bias[out].
    fn conv1x1(&mut self, cin: usize, cout: usize, bias: bool) -> (Mat, Option<Vec<f64>>) {
        let raw = self.take(cout * cin).to_vec();
        let m: Mat = (0..cout).map(|o| raw[o * cin..o * cin + cin].to_vec()).collect();
        let b = if bias { Some(self.take(cout).to_vec()) } else { None };

        (m, b)
    }
}

fn jusize(v: &Value, key: &str) -> usize {
    v.get(key).and_then(Value::as_u64).unwrap_or_else(|| panic!("missing usize `{key}`")) as usize
}

fn jusize_list(v: &Value, key: &str) -> Vec<usize> {
    v.get(key)
        .and_then(Value::as_array)
        .unwrap_or_else(|| panic!("missing list `{key}`"))
        .iter()
        .map(|e| e.as_u64().unwrap() as usize)
        .collect()
}

/// A `{active: true, …}` block, or any other non-null value, counts as present.
fn feature_active(v: Option<&Value>) -> bool {
    match v {
        Some(Value::Object(o)) => o.get("active").and_then(Value::as_bool).unwrap_or(false),
        Some(Value::Null) | None => false,
        Some(_) => true,
    }
}

/// Rejects layer features the generator doesn't model — gating (classic `gated`
/// or v0.7.0 `gating_mode`), FiLM conditioning, a head 1x1, or a bottleneck — so
/// an unsupported `.nam` fails loudly here instead of misreading the weight
/// layout into a silently-wrong clone. (The Dart import path also pre-screens
/// these; this is the generator's own guard.)
fn assert_layer_supported(la: &Value) {
    let gated = la.get("gated").and_then(Value::as_bool).unwrap_or(false)
        || la
            .get("gating_mode")
            .and_then(Value::as_array)
            .is_some_and(|m| m.iter().any(|v| v.as_str() != Some("none")));

    assert!(!gated, "gated WaveNet not supported");

    if let Some(b) = la.get("bottleneck").and_then(Value::as_u64) {
        assert!(b as usize == jusize(la, "channels"), "WaveNet bottleneck not supported");
    }

    assert!(
        !feature_active(la.get("head1x1")) && !feature_active(la.get("head_1x1_config")),
        "WaveNet head 1x1 not supported"
    );

    const FILM: [&str; 9] = [
        "conv_pre_film",
        "conv_post_film",
        "input_mixin_pre_film",
        "input_mixin_post_film",
        "activation_pre_film",
        "activation_post_film",
        "layer1x1_post_film",
        "head1x1_post_film",
        "film_params",
    ];

    assert!(!FILM.iter().any(|k| feature_active(la.get(*k))), "WaveNet FiLM not supported");
}

/// One activation entry, either "Tanh" (str) or {type, negative_slope}.
fn parse_act(v: &Value) -> Act {
    let name = match v {
        Value::String(s) => s.as_str(),
        Value::Object(_) => v.get("type").and_then(Value::as_str).unwrap_or("Tanh"),
        _ => "Tanh",
    };

    match name {
        "Tanh" => Act::Tanh,
        "LeakyReLU" => Act::LeakyRelu(v.get("negative_slope").and_then(Value::as_f64).unwrap_or(0.01)),
        "ReLU" => Act::LeakyRelu(0.0),
        other => panic!("unsupported activation `{other}`"),
    }
}

/// Per-layer activations: a single value broadcasts; a list is taken per layer.
fn layer_acts(cfg: &Value, n: usize) -> Vec<Act> {
    match cfg.get("activation") {
        Some(Value::Array(a)) => a.iter().map(parse_act).collect(),
        Some(other) => vec![parse_act(other); n],
        None => vec![Act::Tanh; n],
    }
}

/// Unwrap a `SlimmableContainer` to its highest-quality (max `max_value`) WaveNet
/// submodel; a plain WaveNet passes through. Returns (config, weights).
fn effective_model(root: &Value) -> (Value, Vec<f64>) {
    if root.get("architecture").and_then(Value::as_str) == Some("SlimmableContainer") {
        let subs = root["config"]["submodels"].as_array().expect("submodels");
        let best = subs
            .iter()
            .max_by(|a, b| {
                let ma = a.get("max_value").and_then(Value::as_f64).unwrap_or(0.0);
                let mb = b.get("max_value").and_then(Value::as_f64).unwrap_or(0.0);

                ma.total_cmp(&mb)
            })
            .expect("at least one submodel");

        return effective_model(&best["model"]);
    }

    let weights = root["weights"]
        .as_array()
        .expect("weights array")
        .iter()
        .map(|v| v.as_f64().unwrap())
        .collect();

    (root["config"].clone(), weights)
}

fn parse_wavenet(config: &Value, weights: &[f64]) -> (Vec<LayerArray>, f64) {
    let mut cur = Cursor { w: weights, pos: 0 };
    let head_scale = config.get("head_scale").and_then(Value::as_f64).unwrap_or(1.0);
    let layers_cfg = config["layers"].as_array().expect("config.layers");

    let layer_arrays = layers_cfg
        .iter()
        .map(|la| {
            assert_layer_supported(la);

            let input_size = jusize(la, "input_size");
            let condition_size = jusize(la, "condition_size");
            let channels = jusize(la, "channels");
            let dilations = jusize_list(la, "dilations");

            // kernel sizes: `kernel_sizes` (list) or a single `kernel_size` (int).
            let kernels: Vec<usize> = match la.get("kernel_sizes") {
                Some(v) => v.as_array().unwrap().iter().map(|e| e.as_u64().unwrap() as usize).collect(),
                None => vec![jusize(la, "kernel_size"); dilations.len()],
            };

            // head_rechannel: `head` = {out_channels, kernel_size, bias} (v0.7.0)
            // or classic `head_size` (int) + `head_bias`, kernel 1.
            let (head_out, head_ks, head_bias) = match la.get("head") {
                Some(h) if h.is_object() => (
                    jusize(h, "out_channels"),
                    jusize(h, "kernel_size"),
                    h.get("bias").and_then(Value::as_bool).unwrap_or(true),
                ),
                _ => (
                    jusize(la, "head_size"),
                    1usize,
                    la.get("head_bias").and_then(Value::as_bool).unwrap_or(false),
                ),
            };

            let acts = layer_acts(la, dilations.len());

            let (rech_w, _) = cur.conv1x1(input_size, channels, false);
            let layers = dilations
                .iter()
                .zip(kernels)
                .zip(acts)
                .map(|((&dil, ks), act)| {
                    let (conv_w, conv_b) = cur.conv1d(channels, channels, ks, true);
                    let (mixin_w, _) = cur.conv1x1(condition_size, channels, false);
                    let (out_w, out_b) = cur.conv1x1(channels, channels, true);

                    Layer { conv_w, conv_b, mixin_w, out_w, out_b: out_b.unwrap(), dil, act }
                })
                .collect();

            let (hr_w, hr_b) = cur.conv1d(channels, head_out, head_ks, head_bias);

            LayerArray { rech_w, layers, hr_w, hr_b, channels }
        })
        .collect();

    (layer_arrays, head_scale)
}

// ---- WaveNet forward pass (channels x T, small channel counts) ----

fn matmul(m: &Mat, x: &[Vec<f64>]) -> Vec<Vec<f64>> {
    let t = x[0].len();

    m.iter()
        .map(|row| {
            (0..t)
                .map(|j| row.iter().enumerate().fold(0.0, |a, (i, &w)| a + w * x[i][j]))
                .collect()
        })
        .collect()
}

fn conv1d_apply(x: &[Vec<f64>], kernels: &[Mat], b: &[f64], dil: usize) -> Vec<Vec<f64>> {
    let cout = kernels[0].len();
    let t = x[0].len();
    let k = kernels.len();

    let mut out = vec![vec![0.0; t]; cout];

    for (ki, kernel) in kernels.iter().enumerate() {
        let offset = (dil as isize) * (ki as isize + 1 - k as isize); // <= 0
        let shift = (-offset) as usize;

        for o in 0..cout {
            for tt in shift..t {
                let src = tt - shift;
                let acc: f64 = kernel[o].iter().enumerate().fold(0.0, |a, (i, &w)| a + w * x[i][src]);
                out[o][tt] += acc;
            }
        }
    }

    for o in 0..cout {
        for tt in 0..t {
            out[o][tt] += b[o];
        }
    }

    out
}

fn activate(act: Act, v: f64) -> f64 {
    match act {
        Act::Tanh => v.tanh(),
        Act::LeakyRelu(slope) => {
            if v >= 0.0 {
                v
            } else {
                slope * v
            }
        }
    }
}

fn run_wavenet(mono: &[f64], las: &[LayerArray], head_scale: f64) -> Vec<f64> {
    let t = mono.len();
    let cond: Vec<Vec<f64>> = vec![mono.to_vec()];

    // head_input threads across layer arrays (see WaveNet.forward); starts empty.
    let mut head: Vec<Vec<f64>> = Vec::new();
    let mut x = cond.clone();

    for la in las {
        let mut xx = matmul(&la.rech_w, &x);

        // Accumulate this array's head input: carry the prior array's head-
        // rechannel output in, then add each layer's post-activation.
        let mut acc: Vec<Vec<f64>> = vec![vec![0.0; t]; la.channels];

        for (i, row) in head.iter().enumerate() {
            if i < acc.len() {
                for (a, &h) in acc[i].iter_mut().zip(row) {
                    *a += h;
                }
            }
        }

        for layer in &la.layers {
            let conv = conv1d_apply(&xx, &layer.conv_w, &layer.conv_b, layer.dil);
            let mixin = matmul(&layer.mixin_w, &cond);

            let post: Vec<Vec<f64>> = conv
                .iter()
                .zip(&mixin)
                .map(|(cr, mr)| cr.iter().zip(mr).map(|(&c, &m)| activate(layer.act, c + m)).collect())
                .collect();

            for (a, pr) in acc.iter_mut().zip(&post) {
                for (av, &pv) in a.iter_mut().zip(pr) {
                    *av += pv;
                }
            }

            let ow = matmul(&layer.out_w, &post);

            for (ci, o) in xx.iter_mut().enumerate() {
                for (ov, &owv) in o.iter_mut().zip(&ow[ci]) {
                    *ov += owv + layer.out_b[ci];
                }
            }
        }

        // head_rechannel is a (possibly temporal) Conv1d over the accumulated head.
        let head_out = conv1d_apply(&acc, &la.hr_w, &la.hr_b, 1);

        x = xx;
        head = head_out;
    }

    head[0].iter().map(|&v| head_scale * v).collect()
}

// ---- DSP: sinc resampling + Welch-averaged Wiener FIR ----

/// Windowed-sinc arbitrary-ratio resample (approximates scipy resample_poly).
fn resample(x: &[f64], up: usize, down: usize) -> Vec<f64> {
    let ratio = up as f64 / down as f64;
    let out_len = ((x.len() as f64) * ratio).floor() as usize;
    let half = 16usize;
    let cutoff = (up.min(down) as f64) / (up.max(down) as f64); // <= 1.0

    (0..out_len)
        .map(|k| {
            let center = k as f64 / ratio; // position in x
            let i0 = center.floor() as isize;

            let mut acc = 0.0;

            for j in (i0 - half as isize)..=(i0 + half as isize) {
                if j < 0 || j as usize >= x.len() {
                    continue;
                }

                let d = center - j as f64;
                let w = cutoff * sinc(cutoff * d) * blackman(d, half as f64);
                acc += x[j as usize] * w;
            }

            acc
        })
        .collect()
}

fn sinc(x: f64) -> f64 {
    if x.abs() < 1e-9 {
        1.0
    } else {
        let p = std::f64::consts::PI * x;

        p.sin() / p
    }
}

fn blackman(d: f64, half: f64) -> f64 {
    if d.abs() > half {
        return 0.0;
    }

    let n = (d + half) / (2.0 * half); // 0..1

    0.42 - 0.5 * (2.0 * std::f64::consts::PI * n).cos() + 0.08 * (4.0 * std::f64::consts::PI * n).cos()
}

// ---- multi-level Wiener-Hammerstein fit -------------------------------------
//
// Fits shared (arrayA, saturator gains, arrayB) so the pedal chain
// `conv(NL(conv(x, A)), B)` tracks the amp at SEVERAL input levels at once.
// arrayA is initialized from the two-level spectral ratio |H_quiet|/|H_loud|
// (hard driving flattens the pre-clip EQ, so the ratio exposes it) as a
// min-phase FIR; then 3 rounds of coordinate descent: deconvolve the target
// saturator output through B, refit the NL by grid+closed-form, refit B by
// multi-level Welch. Validated against the vendor tool's own .clo (matches or
// beats its per-level corr and loudness on clean, drive, and high-gain amps).

use rustfft::num_complex::Complex;

const BINS: usize = NFFT / 2 + 1;
const WELCH_HOP: usize = NFFT / 4;

fn hann() -> Vec<f64> {
    (0..NFFT)
        .map(|i| 0.5 - 0.5 * (2.0 * std::f64::consts::PI * i as f64 / NFFT as f64).cos())
        .collect()
}

/// Welch-averaged cross/auto spectra accumulated over several (x, y) pairs:
/// H = Σ⟨Y·conj(X)⟩ / (Σ⟨|X|²⟩ + reg).
fn welch_pairs(pairs: &[(&[f64], &[f64])], reg: f64) -> Vec<Complex<f64>> {
    let mut planner = RealFftPlanner::<f64>::new();
    let fft = planner.plan_fft_forward(NFFT);
    let win = hann();

    let mut sxy = vec![Complex::new(0.0, 0.0); BINS];
    let mut sxx = vec![0.0f64; BINS];
    let mut xbuf = fft.make_input_vec();
    let mut ybuf = fft.make_input_vec();
    let mut xspec = fft.make_output_vec();
    let mut yspec = fft.make_output_vec();

    for &(x, y) in pairs {
        let mut start = 0;

        while start + NFFT <= x.len().min(y.len()) {
            for i in 0..NFFT {
                xbuf[i] = x[start + i] * win[i];
                ybuf[i] = y[start + i] * win[i];
            }

            fft.process(&mut xbuf, &mut xspec).unwrap();
            fft.process(&mut ybuf, &mut yspec).unwrap();

            for i in 0..BINS {
                sxy[i] += yspec[i] * xspec[i].conj();
                sxx[i] += xspec[i].norm_sqr();
            }

            start += WELCH_HOP;
        }
    }

    let sxx_max = sxx.iter().cloned().fold(0.0f64, f64::max);
    let eps = reg * sxx_max;

    (0..BINS).map(|i| sxy[i] / (sxx[i] + eps)).collect()
}

/// First [n_taps] of the impulse response of spectrum [h].
fn firify(h: &[Complex<f64>], n_taps: usize) -> Vec<f64> {
    let mut planner = RealFftPlanner::<f64>::new();
    let ifft = planner.plan_fft_inverse(NFFT);

    let mut spec = h.to_vec();
    let mut ir = ifft.make_output_vec();

    ifft.process(&mut spec, &mut ir).unwrap();

    ir.iter().take(n_taps).map(|&v| v / NFFT as f64).collect()
}

/// Min-phase FIR ([n_taps]) whose magnitude response matches [mag] (real
/// cepstrum method: log-magnitude → causal cepstral window → exp).
fn minphase_mag(mag: &[f64], n_taps: usize) -> Vec<f64> {
    let mut planner = rustfft::FftPlanner::<f64>::new();
    let fft = planner.plan_fft_forward(NFFT);
    let ifft = planner.plan_fft_inverse(NFFT);

    // full mirrored log-magnitude spectrum
    let mut buf: Vec<Complex<f64>> = (0..NFFT)
        .map(|i| {
            let bin = if i < BINS { i } else { NFFT - i };

            Complex::new(mag[bin].max(1e-9).ln(), 0.0)
        })
        .collect();

    ifft.process(&mut buf); // cepstrum (unnormalized: scale by 1/NFFT below)

    for (i, v) in buf.iter_mut().enumerate() {
        let w = if i == 0 || i == NFFT / 2 {
            1.0
        } else if i < NFFT / 2 {
            2.0
        } else {
            0.0
        };

        *v = Complex::new(v.re / NFFT as f64 * w, 0.0);
    }

    fft.process(&mut buf);

    let mut spec: Vec<Complex<f64>> = buf.iter().map(|v| v.exp()).collect();

    ifft.process(&mut spec);

    spec.iter().take(n_taps).map(|v| v.re / NFFT as f64).collect()
}

/// Smooths a magnitude spectrum over ~1/6 octave (log-frequency), taming Welch
/// variance before the min-phase design.
fn logsmooth(mag: &[f64]) -> Vec<f64> {
    let mut out = mag.to_vec();

    for i in 1..BINS {
        let f = i as f64; // bin index ∝ frequency
        let lo = (f * (2.0f64).powf(-0.5 / 6.0)) as usize;
        let hi = (((f * (2.0f64).powf(0.5 / 6.0)) as usize) + 1).min(BINS);
        let lo = lo.max(1).min(hi - 1);

        out[i] = mag[lo..hi].iter().sum::<f64>() / (hi - lo) as f64;
    }

    out
}

/// Regularized frequency-domain deconvolution of [y] by FIR [b] (overlap-add,
/// Hann analysis+synthesis): the target saturator output the post-filter should
/// have been fed.
fn deconv(y: &[f64], b: &[f64], reg: f64) -> Vec<f64> {
    let mut planner = RealFftPlanner::<f64>::new();
    let fft = planner.plan_fft_forward(NFFT);
    let ifft = planner.plan_fft_inverse(NFFT);
    let win = hann();

    let mut bbuf = fft.make_input_vec();

    for (i, v) in bbuf.iter_mut().enumerate() {
        *v = if i < b.len() { b[i] } else { 0.0 };
    }

    let mut hb = fft.make_output_vec();

    fft.process(&mut bbuf, &mut hb).unwrap();

    let hmax = hb.iter().map(|v| v.norm_sqr()).fold(0.0f64, f64::max);
    let inv: Vec<Complex<f64>> =
        hb.iter().map(|v| v.conj() / (v.norm_sqr() + reg * hmax)).collect();

    let mut out = vec![0.0f64; y.len()];
    let mut norm = vec![0.0f64; y.len()];
    let mut ybuf = fft.make_input_vec();
    let mut yspec = fft.make_output_vec();
    let mut seg = ifft.make_output_vec();
    let mut start = 0;

    while start + NFFT <= y.len() {
        for i in 0..NFFT {
            ybuf[i] = y[start + i] * win[i];
        }

        fft.process(&mut ybuf, &mut yspec).unwrap();

        for (s, i) in yspec.iter_mut().zip(&inv) {
            *s *= i;
        }

        ifft.process(&mut yspec, &mut seg).unwrap();

        for i in 0..NFFT {
            out[start + i] += seg[i] / NFFT as f64 * win[i];
            norm[start + i] += win[i] * win[i];
        }

        start += WELCH_HOP;
    }

    for (o, &n) in out.iter_mut().zip(&norm) {
        *o /= n.max(1e-3);
    }

    out
}

/// The pedal's asymmetric exponential saturator.
fn nl_fwd(v: &[f64], g: &Gains) -> Vec<f64> {
    v.iter()
        .map(|&x| {
            if x > 0.0 {
                g.posmax * (1.0 - (-g.pos_rate * x).max(-60.0).exp())
            } else {
                -g.negmax * (1.0 - (g.neg_rate * x).min(60.0).exp())
            }
        })
        .collect()
}

#[derive(Clone, Copy)]
struct Gains {
    posmax: f64,
    negmax: f64,
    pos_rate: f64,
    neg_rate: f64,
}

/// Fits the saturator to per-level (pre-drive [vs] → target saturator output
/// [ts]) pairs: per sign, grid the rate (log-spaced) and solve the ceiling in
/// closed form (least squares of t ≈ c·(1−e^{−r·v})). Two guards against the
/// fuzz failure mode (an over-hard clipper that squares off all dynamics):
/// - levels are weighted EQUALLY (1/rms of each level's target), so the loud
///   levels — where every hard clipper fits alike — can't dominate;
/// - the rate grid is capped so the knee stays inside the excitation range:
///   r · p90(|v_quietest|) ≤ 1, i.e. the quietest playing level still sits in
///   the curved region (that level-dependence IS the amp's punch). Clean amps
///   never hit the cap (their LS optimum is far below it).
fn fit_nl(vs: &[Vec<f64>], ts: &[Vec<f64>]) -> Gains {
    let stride = 16usize;

    // knee cap from the quietest level's pre-drive envelope (p90 of |v|)
    let vq = vs.last().expect("levels");
    let mut mags: Vec<f64> =
        vq.iter().step_by(stride).map(|v| v.abs()).filter(|&v| v > 1e-8).collect();

    mags.sort_by(f64::total_cmp);

    let p90 = mags.get(mags.len().saturating_mul(9) / 10).copied().unwrap_or(1e-3);
    let r_max = (1.0 / p90.max(1e-9)).max(1.0);
    let r_min = 0.5f64;

    let fit_side = |sign: f64| -> (f64, f64) {
        // per level: (v samples, t samples, weight)
        let pairs: Vec<(Vec<f64>, Vec<f64>, f64)> = vs
            .iter()
            .zip(ts)
            .map(|(v, t)| {
                let mut xs = Vec::new();
                let mut ys = Vec::new();

                for i in (0..v.len().min(t.len())).step_by(stride) {
                    let x = v[i] * sign;

                    if x > 1e-8 {
                        xs.push(x);
                        ys.push(t[i] * sign);
                    }
                }

                let rms =
                    (ys.iter().map(|y| y * y).sum::<f64>() / ys.len().max(1) as f64).sqrt();

                (xs, ys, 1.0 / rms.max(1e-9))
            })
            .collect();

        let mut best = (f64::INFINITY, 1.0, 1.0);
        let n = 80;

        for k in 0..n {
            let r = r_min * (r_max / r_min).powf(k as f64 / (n - 1) as f64);

            let (mut num, mut den) = (0.0, 0.0);

            for (xs, ys, w) in &pairs {
                for (&x, &y) in xs.iter().zip(ys) {
                    let e = 1.0 - (-r * x).max(-60.0).exp();
                    num += w * y * e;
                    den += w * e * e;
                }
            }

            if den < 1e-12 {
                continue;
            }

            let c = num / den;

            if c <= 0.0 {
                continue;
            }

            let resid: f64 = pairs
                .iter()
                .map(|(xs, ys, w)| {
                    let se: f64 = xs
                        .iter()
                        .zip(ys)
                        .map(|(&x, &y)| {
                            let e = 1.0 - (-r * x).max(-60.0).exp();
                            (y - c * e) * (y - c * e)
                        })
                        .sum();

                    w * se / xs.len().max(1) as f64
                })
                .sum();

            if resid < best.0 {
                best = (resid, c, r);
            }
        }

        (best.1, best.2)
    };

    let (posmax, pos_rate) = fit_side(1.0);
    let (negmax, neg_rate) = fit_side(-1.0);

    Gains { posmax, negmax, pos_rate, neg_rate }
}

/// The multi-level fit itself: probe responses come in as (level, response)
/// pairs over [0, RUN_LEN); returns (arrayA48[128], arrayB48[2048], gains).
fn fit_wh_multilevel(
    di48: &[f64],
    resp_by_level: &[(f64, Vec<f64>)],
) -> (Vec<f64>, Vec<f64>, Gains) {
    let seg = |x: &[f64]| -> Vec<f64> { x[FIT_START..FIT_END.min(x.len())].to_vec() };

    let resp_of = |lvl: f64| -> &Vec<f64> {
        &resp_by_level.iter().find(|(l, _)| *l == lvl).expect("probe level missing").1
    };

    let quiet = *FIT_LEVELS.last().unwrap();
    let xs_fit: Vec<Vec<f64>> =
        FIT_LEVELS.iter().map(|&k| seg(di48).iter().map(|v| v * k).collect()).collect();
    let ys_fit: Vec<Vec<f64>> = FIT_LEVELS.iter().map(|&k| seg(resp_of(k))).collect();

    // arrayA init: min-phase of the smoothed two-level ratio, unity at ~1 kHz.
    let x_q: Vec<f64> = seg(di48).iter().map(|v| v * quiet).collect();
    let x_l: Vec<f64> = seg(di48).iter().map(|v| v * LOUD_LEVEL).collect();
    let h_q = welch_pairs(&[(&x_q, &seg(resp_of(quiet)))], 1e-5);
    let h_l = welch_pairs(&[(&x_l, &seg(resp_of(LOUD_LEVEL)))], 1e-5);

    let ratio_raw: Vec<f64> =
        (0..BINS).map(|i| h_q[i].norm() / h_l[i].norm().max(1e-9)).collect();

    let mut ratio = logsmooth(&ratio_raw);
    let bin_1k = 1000 * NFFT / SRC_RATE;
    let norm = ratio[bin_1k].max(1e-9);

    for r in &mut ratio {
        *r /= norm;
    }

    let a48 = minphase_mag(&ratio, ARRAY_A_LEN);

    // arrayB init: the hard-driven transfer (pre-clip EQ flattened ≈ B's shape).
    let mut b48 = firify(&h_l, ARRAY_B_LEN);

    // Coordinate descent: NL from deconvolved targets, B from multi-level Welch.
    let vs: Vec<Vec<f64>> = xs_fit.iter().map(|x| conv_fir(x, &a48)).collect();
    let mut gains = Gains { posmax: 1.0, negmax: 1.0, pos_rate: 1.0, neg_rate: 1.0 };

    for _ in 0..3 {
        let ts: Vec<Vec<f64>> = ys_fit.iter().map(|y| deconv(y, &b48, 3e-3)).collect();

        gains = fit_nl(&vs, &ts);

        let us: Vec<Vec<f64>> = vs.iter().map(|v| nl_fwd(v, &gains)).collect();
        let pairs: Vec<(&[f64], &[f64])> =
            us.iter().zip(&ys_fit).map(|(u, y)| (u.as_slice(), y.as_slice())).collect();

        b48 = firify(&welch_pairs(&pairs, 1e-5), ARRAY_B_LEN);
    }

    (a48, b48, gains)
}

/// Direct FIR convolution (kernel ≤ 128 taps — cheap next to the FFT stages).
fn conv_fir(x: &[f64], h: &[f64]) -> Vec<f64> {
    let mut y = vec![0.0f64; x.len()];

    for (k, &hk) in h.iter().enumerate() {
        if hk == 0.0 {
            continue;
        }

        for t in k..x.len() {
            y[t] += hk * x[t - k];
        }
    }

    y
}

// ---- public entry ----

/// Generates the clone-model arrays from a `.nam` (JSON) and the fixed reference
/// DI (mono, 44.1 kHz). Probes the amp model at several input levels (threaded —
/// one WaveNet pass per level), multi-level-fits the Wiener-Hammerstein chain,
/// and returns arrays at the device rate, ready for the `.clo`.
pub fn generate_clo_arrays(nam_json: String, reference_di_44100: Vec<f32>) -> CloArrays {
    let root: Value = serde_json::from_str(&nam_json).expect("invalid .nam JSON");
    let (config, weights) = effective_model(&root);
    let (las, head_scale) = parse_wavenet(&config, &weights);

    let di44: Vec<f64> = reference_di_44100.iter().map(|&v| v as f64).collect();
    let mut di48 = resample(&di44, SRC_RATE, DEVICE_RATE);

    di48.truncate(RUN_LEN); // the fit only reads [0, RUN_LEN)

    let resp_by_level = probe_levels(&di48, &las, head_scale);
    let (a48, b48, gains) = fit_wh_multilevel(&di48, &resp_by_level);

    let fir_a = resample(&a48, DEVICE_RATE, SRC_RATE);
    let fir_b = resample(&b48, DEVICE_RATE, SRC_RATE);

    let mut array_a = vec![0.0f32; ARRAY_A_LEN];

    for (i, &v) in fir_a.iter().take(ARRAY_A_LEN).enumerate() {
        array_a[i] = v as f32;
    }

    let mut array_b = vec![0.0f32; ARRAY_B_LEN];

    for (i, &v) in fir_b.iter().take(ARRAY_B_LEN).enumerate() {
        array_b[i] = v as f32;
    }

    CloArrays {
        array_a,
        array_b,
        gains: vec![
            gains.posmax as f32,
            gains.negmax as f32,
            gains.pos_rate as f32,
            gains.neg_rate as f32,
        ],
    }
}

/// Runs the WaveNet over the DI at every probe level, one thread per level (the
/// forward pass is single-threaded; levels are independent).
fn probe_levels(di48: &[f64], las: &[LayerArray], head_scale: f64) -> Vec<(f64, Vec<f64>)> {
    let mut levels: Vec<f64> = FIT_LEVELS.to_vec();

    levels.push(LOUD_LEVEL);

    // wasm32 has no `std::thread`; the probe levels are independent, so run them
    // sequentially there. Native keeps one thread per level for speed.
    #[cfg(target_arch = "wasm32")]
    {
        levels
            .iter()
            .map(|&k| {
                let x: Vec<f64> = di48.iter().map(|v| v * k).collect();

                (k, run_wavenet(&x, las, head_scale))
            })
            .collect()
    }

    #[cfg(not(target_arch = "wasm32"))]
    {
        std::thread::scope(|s| {
            let handles: Vec<_> = levels
                .iter()
                .map(|&k| {
                    s.spawn(move || {
                        let x: Vec<f64> = di48.iter().map(|v| v * k).collect();

                        (k, run_wavenet(&x, las, head_scale))
                    })
                })
                .collect();

            handles.into_iter().map(|h| h.join().expect("probe thread panicked")).collect()
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The large reference-signal fixtures are gitignored (regenerable). Skip
    /// the data-driven tests when they are absent (fresh checkout / CI).
    fn fixtures_present() -> bool {
        std::path::Path::new("tests/fixtures/di48.f32").exists()
    }

    fn read_f32(path: &str) -> Vec<f64> {
        let bytes = std::fs::read(path).unwrap();

        bytes
            .chunks_exact(4)
            .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]) as f64)
            .collect()
    }

    fn load_wavenet(path: &str) -> (Vec<LayerArray>, f64) {
        let root: Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let (config, weights) = effective_model(&root);

        parse_wavenet(&config, &weights)
    }

    fn corr(a: &[f64], b: &[f64]) -> f64 {
        let n = a.len().min(b.len());
        let ma = a[..n].iter().sum::<f64>() / n as f64;
        let mb = b[..n].iter().sum::<f64>() / n as f64;

        let mut num = 0.0;
        let mut da = 0.0;
        let mut db = 0.0;

        for i in 0..n {
            let x = a[i] - ma;
            let y = b[i] - mb;
            num += x * y;
            da += x * x;
            db += y * y;
        }

        num / (da.sqrt() * db.sqrt())
    }

    #[test]
    fn wavenet_inference_matches_reference() {
        if !fixtures_present() {
            return;
        }

        let (las, head_scale) = load_wavenet("tests/fixtures/ref_input.nam");

        let di48 = read_f32("tests/fixtures/di48.f32");
        let target = read_f32("tests/fixtures/target48.f32");

        let out = run_wavenet(&di48, &las, head_scale);
        // Best-scalar-gain aside, the shape must match the tool's render.
        let c = corr(&out, &target);

        assert!(c > 0.999, "inference corr too low: {c}");
    }

    /// v0.7.0 / SlimmableContainer WaveNet (per-layer kernels, LeakyReLU, temporal
    /// head_rechannel): our forward pass must match the reference nam package's
    /// inference of the same amp over the same DI. Ground truth is `ac30_resp48`
    /// (nam `forward(pad_start=True)` output; see tools/re/nam ground-truth script).
    #[test]
    fn slimmable_inference_matches_nam_reference() {
        if !std::path::Path::new("tests/fixtures/ac30_resp48.f32").exists() {
            return;
        }

        let (las, head_scale) = load_wavenet("tests/fixtures/ac30_full.nam");
        let di48 = read_f32("tests/fixtures/di48.f32");
        let reference = read_f32("tests/fixtures/ac30_resp48.f32");

        let out = run_wavenet(&di48, &las, head_scale);
        let c = corr(&out, &reference);

        assert!(c > 0.999, "slimmable inference corr too low: {c}");
    }

    /// PEDAL-ACCURATE multi-level check: fit the chain on the reference amp,
    /// then play conv(NL(conv(di·k, A)), B) at 48k against the amp's response at
    /// each fit level. Shape (corr) AND loudness must track at EVERY level — a
    /// single-level check is exactly the blind spot that shipped clean-sounding
    /// high-gain clones. Thresholds from the validated Python reference
    /// (ref amp: corr ≈ 0.88 flat across levels, level 0.48–1.4).
    #[test]
    fn generator_tracks_the_amp_across_levels() {
        if !fixtures_present() {
            return;
        }

        let (las, hs) = load_wavenet("tests/fixtures/ref_input.nam");
        let mut di48 = read_f32("tests/fixtures/di48.f32");

        di48.truncate(RUN_LEN);

        let resp_by_level = probe_levels(&di48, &las, hs);
        let (a48, b48, gains) = fit_wh_multilevel(&di48, &resp_by_level);

        assert!(gains.posmax > 0.0 && gains.posmax < 2.0, "POSMAX sane: {}", gains.posmax);
        assert!(gains.pos_rate > 0.5, "pos_rate degenerate: {}", gains.pos_rate);

        let nonzero = b48.iter().filter(|&&v| v != 0.0).count();

        assert!(nonzero > 1000, "arrayB looks degenerate: {nonzero} nonzero");

        // Held-out window inside the probed region, past the fit segment start.
        let (s, l) = (FIT_END - 300_000, 250_000usize);

        for &(k, ref resp) in &resp_by_level {
            if k == LOUD_LEVEL {
                continue; // probe-only level (arrayA init), not a fit target
            }

            let x: Vec<f64> = di48.iter().map(|v| v * k).collect();
            let u = nl_fwd(&conv_fir(&x, &a48), &gains);
            let mut y = vec![0.0f64; l];

            for i in 0..l {
                let mut acc = 0.0;

                for (t, &h) in b48.iter().enumerate() {
                    if s + i >= t {
                        acc += h * u[s + i - t];
                    }
                }

                y[i] = acc;
            }

            let c = corr(&y, &resp[s..s + l]);
            let rms = |v: &[f64]| (v.iter().map(|a| a * a).sum::<f64>() / v.len() as f64).sqrt();
            let level = rms(&y) / rms(&resp[s..s + l]);

            assert!(c.abs() > 0.82, "corr too low at level {k}: {c}");
            assert!(
                level > 0.3 && level < 2.5,
                "loudness off at level {k}: {level}x"
            );
        }
    }
}
