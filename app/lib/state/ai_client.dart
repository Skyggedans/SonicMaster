import 'dart:math';

/// The time budget shared by all the requests made for a single preset.
const aiTimeout = Duration(seconds: 90);

/// The most requests (one per model) made for a single preset.
const aiMaxAttempts = 3;

/// A failed AI request, with a message fit for the UI.
class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A provider that can answer a prompt with a JSON document. Subclasses supply
/// the models and the single-request call; this class picks models at random
/// and retries with others, within a shared time budget.
abstract class AiClient {
  AiClient({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// The models to pick from. One is chosen at random, and the others are the
  /// fallbacks when it fails.
  List<String> get models;

  /// One request to [model], abandoned after [timeout]. Throws [AiException]
  /// on a transport, API or malformed-response failure.
  Future<Map<String, dynamic>> requestJson(
    String model,
    String systemPrompt,
    String prompt,
    Duration timeout,
  );

  /// Asks the model to answer [prompt] under [systemPrompt] with a JSON
  /// document, and returns it decoded. Starts with a random model from
  /// [models] and, on failure, tries other models, up to [aiMaxAttempts]
  /// requests within a total of [aiTimeout]: each request gets what is left of
  /// it after the failed ones. Throws the last [AiException] when all of them
  /// fail.
  Future<Map<String, dynamic>> generateJson({
    required String systemPrompt,
    required String prompt,
  }) async {
    final shuffled = [...models]..shuffle(_random);
    final clock = Stopwatch()..start();
    AiException? last;

    for (final model in shuffled.take(aiMaxAttempts)) {
      final remaining = aiTimeout - clock.elapsed;

      if (remaining <= Duration.zero) break;

      try {
        return await requestJson(model, systemPrompt, prompt, remaining);
      } on AiException catch (e) {
        last = e;
      }
    }

    throw last!;
  }

  void close();
}
