import 'openai_compatible_client.dart';

/// The OpenAI models used to generate presets.
const chatGptModels = ['gpt-4.1', 'gpt-4.1-mini', 'gpt-4o'];

/// Client for the OpenAI Chat Completions API (ChatGPT models).
class ChatGptClient extends OpenAiCompatibleClient {
  ChatGptClient({required super.apiKey, super.client, super.random});

  @override
  List<String> get models => chatGptModels;

  @override
  String get providerName => 'ChatGPT';

  @override
  String get host => 'api.openai.com';

  @override
  String get path => '/v1/chat/completions';
}
