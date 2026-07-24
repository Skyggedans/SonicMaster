import 'dart:convert';

/// Human-readable list of the `.nam` model formats the clone converter accepts,
/// shown in the import-error dialog.
const supportedNamFormats = <String>[
  'NAM WaveNet — standard (v0.5.x – v0.7.x)',
  'NAM WaveNet inside a SlimmableContainer (Tone3000 v0.7.0)',
];

/// A `.nam` whose architecture the converter can't clone. [architecture] is the
/// detected model type, surfaced in the error dialog.
class UnsupportedNamFormat implements Exception {
  const UnsupportedNamFormat(this.architecture);

  final String architecture;

  @override
  String toString() => 'Unsupported NAM architecture: $architecture';
}

/// The FiLM-conditioning keys a v0.7.0 WaveNet layer may carry. The native
/// generator doesn't model FiLM, so their weights would be misread silently.
const _filmKeys = <String>[
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

/// Inspects [namJson] and throws [UnsupportedNamFormat] unless the converter can
/// clone it: a WaveNet (directly, or the WaveNet submodel of a SlimmableContainer)
/// that uses only the plain layer features the native generator models. A parse
/// failure reports architecture "unreadable".
void assertNamSupported(String namJson) {
  final Object? decoded;

  try {
    decoded = jsonDecode(namJson);
  } catch (_) {
    throw const UnsupportedNamFormat('unreadable (not valid .nam JSON)');
  }

  if (decoded is! Map) {
    throw const UnsupportedNamFormat('unreadable (not valid .nam JSON)');
  }

  _assertLayersSupported(_effectiveWaveNet(decoded));
}

/// The WaveNet the converter will actually run: a plain WaveNet passes through; a
/// SlimmableContainer resolves to its highest-quality (max `max_value`) WaveNet
/// submodel (matching the Rust generator). Throws for anything else.
Map _effectiveWaveNet(Map root) {
  final arch = root['architecture'];

  if (arch == 'WaveNet') return root;

  if (arch == 'SlimmableContainer') {
    final submodels = (root['config'] as Map?)?['submodels'];
    Map? best;
    num bestValue = double.negativeInfinity;

    if (submodels is List) {
      for (final s in submodels.whereType<Map>()) {
        final model = s['model'];
        final value = (s['max_value'] as num?) ?? 0;

        if (model is Map &&
            model['architecture'] == 'WaveNet' &&
            value >= bestValue) {
          best = model;
          bestValue = value;
        }
      }
    }

    if (best != null) return best;

    throw const UnsupportedNamFormat(
      'SlimmableContainer (no WaveNet submodel)',
    );
  }

  throw UnsupportedNamFormat(arch is String ? arch : 'unknown');
}

/// Rejects WaveNet layer features the native generator doesn't model — gating,
/// FiLM conditioning, a head 1x1, or a bottleneck — which would otherwise be
/// misparsed into a silently-wrong clone.
void _assertLayersSupported(Map wavenet) {
  final layers = (wavenet['config'] as Map?)?['layers'];

  if (layers is! List) return;

  for (final layer in layers.whereType<Map>()) {
    if (layer['gated'] == true) {
      throw const UnsupportedNamFormat('gated WaveNet');
    }

    final gatingModes = layer['gating_mode'];

    if (gatingModes is List && gatingModes.any((m) => m != 'none')) {
      throw const UnsupportedNamFormat('gated WaveNet');
    }

    final bottleneck = layer['bottleneck'];

    if (bottleneck != null && bottleneck != layer['channels']) {
      throw const UnsupportedNamFormat('WaveNet with a bottleneck');
    }

    if (_isActive(layer['head1x1']) || _isActive(layer['head_1x1_config'])) {
      throw const UnsupportedNamFormat('WaveNet with a head 1x1');
    }

    if (_filmKeys.any((k) => _isActive(layer[k]))) {
      throw const UnsupportedNamFormat('WaveNet with FiLM conditioning');
    }
  }
}

/// A config sub-block counts as active if it's a `{active: true, …}` map, or any
/// other non-null/non-false value.
bool _isActive(Object? value) =>
    value is Map ? value['active'] == true : value != null && value != false;

/// Whether a conversion-stage error message looks like a model-format problem
/// (e.g. a WaveNet variant the native generator rejects), so the dialog can list
/// the supported formats rather than show a bare error.
bool looksLikeNamFormatError(Object error) {
  final text = error.toString().toLowerCase();

  return text.contains('invalid .nam') ||
      text.contains('unsupported activation') ||
      text.contains('gated') ||
      text.contains('not supported') ||
      text.contains('missing');
}
