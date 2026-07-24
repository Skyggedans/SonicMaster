import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/nam_format.dart';

void main() {
  group('assertNamSupported', () {
    test('accepts a plain WaveNet', () {
      final json = jsonEncode({
        'architecture': 'WaveNet',
        'config': {'layers': []},
      });

      expect(() => assertNamSupported(json), returnsNormally);
    });

    test('accepts a SlimmableContainer with a WaveNet submodel', () {
      final json = jsonEncode({
        'architecture': 'SlimmableContainer',
        'config': {
          'submodels': [
            {
              'max_value': 1,
              'model': {'architecture': 'WaveNet'},
            },
          ],
        },
      });

      expect(() => assertNamSupported(json), returnsNormally);
    });

    test('rejects LSTM with the architecture name', () {
      final json = jsonEncode({'architecture': 'LSTM', 'config': {}});

      expect(
        () => assertNamSupported(json),
        throwsA(
          isA<UnsupportedNamFormat>().having(
            (e) => e.architecture,
            'architecture',
            'LSTM',
          ),
        ),
      );
    });

    test('rejects a SlimmableContainer with no WaveNet submodel', () {
      final json = jsonEncode({
        'architecture': 'SlimmableContainer',
        'config': {
          'submodels': [
            {
              'model': {'architecture': 'LSTM'},
            },
          ],
        },
      });

      expect(
        () => assertNamSupported(json),
        throwsA(isA<UnsupportedNamFormat>()),
      );
    });

    test('rejects unreadable JSON', () {
      expect(
        () => assertNamSupported('not json {'),
        throwsA(isA<UnsupportedNamFormat>()),
      );
    });

    test('rejects a WaveNet with FiLM conditioning', () {
      final json = jsonEncode({
        'architecture': 'WaveNet',
        'config': {
          'layers': [
            {
              'channels': 8,
              'conv_pre_film': {'active': true},
            },
          ],
        },
      });

      expect(
        () => assertNamSupported(json),
        throwsA(isA<UnsupportedNamFormat>()),
      );
    });

    test('rejects a v0.7.0 gated (gating_mode) WaveNet', () {
      final json = jsonEncode({
        'architecture': 'WaveNet',
        'config': {
          'layers': [
            {
              'channels': 8,
              'gating_mode': ['none', 'gated'],
            },
          ],
        },
      });

      expect(
        () => assertNamSupported(json),
        throwsA(isA<UnsupportedNamFormat>()),
      );
    });

    test('rejects a WaveNet with a head 1x1', () {
      final json = jsonEncode({
        'architecture': 'WaveNet',
        'config': {
          'layers': [
            {
              'channels': 8,
              'head1x1': {'active': true},
            },
          ],
        },
      });

      expect(
        () => assertNamSupported(json),
        throwsA(isA<UnsupportedNamFormat>()),
      );
    });

    test('accepts a plain WaveNet whose layers use no exotic features', () {
      final json = jsonEncode({
        'architecture': 'WaveNet',
        'config': {
          'layers': [
            {
              'channels': 8,
              'gating_mode': ['none', 'none'],
              'conv_pre_film': {'active': false},
            },
          ],
        },
      });

      expect(() => assertNamSupported(json), returnsNormally);
    });
  });

  test('looksLikeNamFormatError matches generator format panics', () {
    expect(looksLikeNamFormatError('invalid .nam JSON'), isTrue);
    expect(looksLikeNamFormatError('unsupported activation `Swish`'), isTrue);
    expect(looksLikeNamFormatError('gated WaveNet not supported'), isTrue);
    expect(looksLikeNamFormatError('connection reset'), isFalse);
  });
}
