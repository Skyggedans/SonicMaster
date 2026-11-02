import 'dart:convert';

import 'package:http/http.dart' as http;

/// The Gemini model used to generate presets.
const geminiModel = 'gemini-3.6-flash';

/// A failed Gemini request, with a message fit for the UI.
class GeminiException implements Exception {
  const GeminiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Minimal client for the Gemini `generateContent` REST endpoint.
class GeminiClient {
  GeminiClient({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  /// Asks the model to answer [prompt] under [systemPrompt] with a JSON
  /// document, and returns it decoded. Throws [GeminiException] on a transport,
  /// API or malformed-response failure.
  Future<Map<String, dynamic>> generateJson({
    required String systemPrompt,
    required String prompt,
  }) async {
    final http.Response res;

    try {
      res = await _client
          .post(
            Uri.https(
              'generativelanguage.googleapis.com',
              '/v1beta/models/$geminiModel:generateContent',
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
          .timeout(const Duration(seconds: 90));
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
