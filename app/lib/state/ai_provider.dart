import 'ai_client.dart';
import 'chatgpt_client.dart';
import 'deepseek_client.dart';
import 'gemini_client.dart';

/// The LLM services a preset can be generated with.
enum AiProvider {
  gemini('Gemini'),
  chatGpt('ChatGPT'),
  deepSeek('DeepSeek');

  const AiProvider(this.label);

  final String label;

  /// A client for this provider authenticated with [apiKey].
  AiClient createClient(String apiKey) => switch (this) {
    gemini => GeminiClient(apiKey: apiKey),
    chatGpt => ChatGptClient(apiKey: apiKey),
    deepSeek => DeepSeekClient(apiKey: apiKey),
  };
}
