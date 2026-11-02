import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../state/ai_prefs.dart';
import '../state/ai_preset.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';
import 'sonic_field.dart';

/// Presents [AiPresetDialog]. Resolves to true once a preset was generated and
/// pushed to the pedal.
Future<bool?> showAiPresetDialog(BuildContext context) {
  return showSonicDialog<bool>(
    context: context,
    builder: (_) => const AiPresetDialog(),
  );
}

/// Describe a tone in words; Gemini designs a preset for it and the app pushes
/// it to the pedal (the same path as Import). The API key is the user's own and
/// stays on this device.
class AiPresetDialog extends HookConsumerWidget {
  const AiPresetDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.read(aiPrefsProvider);
    final prompt = useTextEditingController();
    final apiKey = useTextEditingController(text: prefs.geminiApiKey ?? '');
    final isBusy = useState(false);
    final error = useState<String?>(null);

    final promptText = useValueListenable(prompt).text;
    final keyText = useValueListenable(apiKey).text;
    final canGenerate =
        !isBusy.value &&
        promptText.trim().isNotEmpty &&
        keyText.trim().isNotEmpty;

    Future<void> generate() async {
      isBusy.value = true;
      error.value = null;

      try {
        await prefs.saveGeminiApiKey(apiKey.text);
        await generateAiPreset(ref, promptText.trim());

        if (context.mounted) Navigator.pop(context, true);
      } catch (e) {
        if (!context.mounted) return;

        error.value = e is FormatException
            ? 'Invalid preset: ${e.message}'
            : '$e';
        isBusy.value = false;
      }
    }

    // Block dismissal while the request is in flight, so the WidgetRef isn't
    // disposed before generateAiPreset's post-await provider reads run.
    return PopScope(
      canPop: !isBusy.value,
      child: SonicDialog(
        maxWidth: 460,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            const Text('Generate preset with AI', style: AppText.dialogTitle),
            const SizedBox(height: 12),
            const Text('Describe the tone', style: AppText.inputLabel),
            const SizedBox(height: 6),
            SonicField(
              controller: prompt,
              autofocus: true,
              maxLines: 4,
              hintText: 'e.g. Mr. Crowley by Ozzy Osbourne, solo tone',
              style: AppText.input,
            ),
            const SizedBox(height: 14),
            const Text('Gemini API key', style: AppText.inputLabel),
            const SizedBox(height: 6),
            SonicField(
              controller: apiKey,
              hintText: 'Stored on this device only',
              style: AppText.input,
              autocorrect: false,
              enableSuggestions: false,
            ),
            if (error.value != null) ...[
              const SizedBox(height: 12),
              Text(
                error.value!,
                style: AppText.dialogBody.copyWith(color: Palette.error),
              ),
            ],
            if (isBusy.value) ...[
              const SizedBox(height: 14),
              const Row(
                children: [
                  SonicSpinner(size: 22),
                  SizedBox(width: 14),
                  Text('Designing your preset…', style: AppText.dialogBody),
                ],
              ),
            ],
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: .end,
              children: [
                SonicButton(
                  label: 'Cancel',
                  onPressed: isBusy.value
                      ? null
                      : () => Navigator.pop(context, false),
                ),
                const SizedBox(width: 10),
                SonicButton(
                  label: 'Generate',
                  isAccent: true,
                  onPressed: canGenerate ? generate : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
