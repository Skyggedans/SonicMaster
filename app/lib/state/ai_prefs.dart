import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's own Gemini API key, kept on this device only.
class AiPrefs {
  AiPrefs(this._prefs);

  final SharedPreferences _prefs;

  static const _geminiKey = 'gemini_api_key';

  String? get geminiApiKey => _prefs.getString(_geminiKey);

  /// Stores [key]; null or blank clears it.
  Future<void> saveGeminiApiKey(String? key) async {
    final k = key?.trim();

    if (k == null || k.isEmpty) {
      await _prefs.remove(_geminiKey);
    } else {
      await _prefs.setString(_geminiKey, k);
    }
  }
}

/// The app's [AiPrefs]. Overridden in `main()` with a loaded instance.
final aiPrefsProvider = Provider<AiPrefs>(
  (_) => throw UnimplementedError(
    'aiPrefsProvider must be overridden in the root ProviderScope',
  ),
);
