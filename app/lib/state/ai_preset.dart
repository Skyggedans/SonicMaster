import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/preset_json.dart';
import '../model/preset_prompt.dart';
import 'ai_prefs.dart';
import 'data_providers.dart';
import 'device_providers.dart';
import 'gemini_client.dart';
import 'preset_io.dart';

/// Asks Gemini for a preset matching [description] and pushes it to the
/// connected pedal (live state only — Save persists it to a slot).
///
/// Throws [GeminiException] when there is no API key or the request fails, and
/// [FormatException] when the answer isn't a valid preset (e.g. an effect the
/// pedal doesn't have).
Future<void> generateAiPreset(WidgetRef ref, String description) async {
  final data = ref.read(dataAssetsProvider).valueOrNull;
  final key = ref.read(aiPrefsProvider).geminiApiKey;

  if (data == null) throw const GeminiException('Device data not loaded yet');

  if (key == null) throw const GeminiException('Enter your Gemini API key');

  final client = GeminiClient(apiKey: key);

  final ImportedPreset imported;

  try {
    final json = await client.generateJson(
      systemPrompt: buildPresetSystemPrompt(
        data,
        ref.read(effectiveDeviceModelProvider),
      ),
      prompt: description,
    );

    imported = importedPresetFromJson(json, data);
  } finally {
    client.close();
  }

  await pushImportedPreset(ref, imported);
}
