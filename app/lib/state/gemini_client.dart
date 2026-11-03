import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// The Gemini models used to generate presets. One is picked at random, and
/// the others are the fallbacks when it fails.
const geminiModels = [
  'gemini-4-argon',
  'gemini-3.8-flash',
  'gemini-3.6-flash',
  'gemini-3.5-flash-lite',
];

/// The time budget shared by all the requests made for a single preset.
const geminiTimeout = Duration(seconds: 90);

/// The most requests (one per model) made for a single preset.
const geminiMaxAttempts = 3;

/// A failed Gemini request, with a message fit for the UI.
class GeminiException implements Exception {
  const GeminiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Minimal client for the Gemini `generateContent` REST endpoint.
class GeminiClient {
  GeminiClient({required this.apiKey, http.Client? client, Random? random})
    : _client = client ?? http.Client(),
      _random = random ?? Random();

  final String apiKey;
  final http.Client _client;
  final Random _random;

  /// Asks the model to answer [prompt] under [systemPrompt] with a JSON
  /// document, and returns it decoded. Starts with a random model from
  /// [geminiModels] and, on failure, tries other models, up to
  /// [geminiMaxAttempts] requests within a total of [geminiTimeout]: each
  /// request gets what is left of it after the failed ones. Throws the last
  /// [GeminiException] when all of them fail.
  Future<Map<String, dynamic>> generateJson({
    required String systemPrompt,
    required String prompt,
  }) async {
    final models = [...geminiModels]..shuffle(_random);
    final clock = Stopwatch()..start();
    GeminiException? last;

    for (final model in models.take(geminiMaxAttempts)) {
      final remaining = geminiTimeout - clock.elapsed;

      if (remaining <= Duration.zero) break;

      try {
        return await _generateJson(model, systemPrompt, prompt, remaining);
      } on GeminiException catch (e) {
        last = e;
      }
    }

    throw last!;
  }

  /// One request to [model], abandoned after [timeout]. Throws
  /// [GeminiException] on a transport, API or malformed-response failure.
  Future<Map<String, dynamic>> _generateJson(
    String model,
    String systemPrompt,
    String prompt,
    Duration timeout,
  ) async {
    final http.Response res;

    try {
      res = await _client
          .post(
            Uri.https(
              'generativelanguage.googleapis.com',
              '/v1beta/models/$model:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'X-goog-api-key': apiKey,
            },
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': systemPrompt},
                ],
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'responseMimeType': 'application/json',
                'temperature': 0.7,
              },
            }),
          )
          .timeout(timeout);
    } catch (e) {
      throw GeminiException('Could not reach Gemini: $e');
    }

    final Object? body;

    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw GeminiException(
        'Gemini returned an unreadable response (${res.statusCode})',
      );
    }

    if (res.statusCode != 200) {
      final error = body is Map ? body['error'] : null;
      final msg = error is Map ? error['message'] : null;

      throw GeminiException(
        'Gemini error ${res.statusCode}${msg == null ? '' : ': $msg'}',
      );
    }

    try {
      final text =
          ((((body as Map)['candidates'] as List).first as Map)['content']
                  as Map)['parts']
              as List;
      final json = jsonDecode((text.first as Map)['text'] as String);

      return (json as Map).cast<String, dynamic>();
    } catch (_) {
      throw const GeminiException(
        'Gemini did not return a valid preset (empty or blocked response)',
      );
    }
  }

  void close() => _client.close();
}
