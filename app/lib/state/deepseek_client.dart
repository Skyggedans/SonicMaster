import 'openai_compatible_client.dart';

/// The DeepSeek models used to generate presets.
const deepSeekModels = ['deepseek-chat', 'deepseek-reasoner'];

/// Client for the DeepSeek Chat Completions API.
class DeepSeekClient extends OpenAiCompatibleClient {
  DeepSeekClient({required super.apiKey, super.client, super.random});

  @override
  List<String> get models => deepSeekModels;

  @override
  String get providerName => 'DeepSeek';

  @override
  String get host => 'api.deepseek.com';

  @override
  String get path => '/chat/completions';
}
