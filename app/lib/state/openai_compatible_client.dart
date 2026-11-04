import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_client.dart';

/// Client for an OpenAI-style `/chat/completions` endpoint, answering in JSON
/// mode. [ChatGptClient] and [DeepSeekClient] only differ in host, path and
/// models.
abstract class OpenAiCompatibleClient extends AiClient {
  OpenAiCompatibleClient({
    required this.apiKey,
    http.Client? client,
    super.random,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  /// The provider's name, for error messages.
  String get providerName;

  String get host;

  String get path;

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
            Uri.https(host, path),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': prompt},
              ],
              'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(timeout);
    } catch (e) {
      throw AiException('Could not reach $providerName: $e');
    }

    final Object? body;

    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw AiException(
        '$providerName returned an unreadable response (${res.statusCode})',
      );
    }

    if (res.statusCode != 200) {
      final error = body is Map ? body['error'] : null;
      final msg = error is Map ? error['message'] : null;

      throw AiException(
        '$providerName error ${res.statusCode}${msg == null ? '' : ': $msg'}',
      );
    }

    try {
      final message =
          (((body as Map)['choices'] as List).first as Map)['message'] as Map;
      final json = jsonDecode(message['content'] as String);

      return (json as Map).cast<String, dynamic>();
    } catch (_) {
      throw AiException(
        '$providerName did not return a valid preset (empty or blocked '
        'response)',
      );
    }
  }

  @override
  void close() => _client.close();
}
