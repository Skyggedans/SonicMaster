import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_provider.dart';

/// The user's chosen AI provider and their own API key for each, kept on this
/// device only.
class AiPrefs {
  AiPrefs(this._prefs);

  final SharedPreferences _prefs;

  static const _providerKey = 'ai_provider';

  // gemini keeps the key name from before other providers existed.
  static String _keyName(AiProvider p) => switch (p) {
    .gemini => 'gemini_api_key',
    .chatGpt => 'chatgpt_api_key',
    .deepSeek => 'deepseek_api_key',
  };

  /// The provider last used; Gemini until one is chosen.
  AiProvider get provider {
    final name = _prefs.getString(_providerKey);

    return AiProvider.values.where((p) => p.name == name).firstOrNull ??
        AiProvider.gemini;
  }

  Future<void> saveProvider(AiProvider provider) =>
      _prefs.setString(_providerKey, provider.name);

  String? apiKey(AiProvider provider) =>
      _prefs.getString(_keyName(provider));

  /// Stores [key] for [provider]; null or blank clears it.
  Future<void> saveApiKey(AiProvider provider, String? key) async {
    final k = key?.trim();

    if (k == null || k.isEmpty) {
      await _prefs.remove(_keyName(provider));
    } else {
      await _prefs.setString(_keyName(provider), k);
    }
  }
}

/// The app's [AiPrefs]. Overridden in `main()` with a loaded instance.
final aiPrefsProvider = Provider<AiPrefs>(
  (_) => throw UnimplementedError(
    'aiPrefsProvider must be overridden in the root ProviderScope',
  ),
);
