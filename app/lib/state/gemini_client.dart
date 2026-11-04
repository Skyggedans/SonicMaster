import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_client.dart';

/// The Gemini models used to generate presets.
const geminiModels = [
  'gemini-3.6-flash',
  'gemini-3.8-flash',
  'gemini-4-argon',
  'gemini-3.5-flash-lite',
  'gemini-2.5-flash',
];

/// Minimal client for the Gemini `generateContent` REST endpoint.
class GeminiClient extends AiClient {
  GeminiClient({required this.apiKey, http.Client? client, super.random})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  List<String> get models => geminiModels;

  @override
  Future<Map<String, dynamic>> requestJson(
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
      throw AiException('Could not reach Gemini: $e');
    }

    final Object? body;

    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw AiException(
        'Gemini returned an unreadable response (${res.statusCode})',
      );
    }

    if (res.statusCode != 200) {
      final error = body is Map ? body['error'] : null;
      final msg = error is Map ? error['message'] : null;

      throw AiException(
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
      throw const AiException(
        'Gemini did not return a valid preset (empty or blocked response)',
      );
    }
  }

  @override
  void close() => _client.close();
}
