import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../state/preset_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';
import 'sonic_field.dart';

/// Name + target-slot dialog for saving the current edits to flash (`040A`).
class SavePresetDialog extends HookConsumerWidget {
  const SavePresetDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Empty default: the loaded preset's *label* (e.g. "P05"/"F03") is not its
    // real stored name, and offering it — especially a Factory label for a
    // User-slot save — would write a misleading name to flash.
    final name = useTextEditingController();
    final nameText = useValueListenable(name).text;

    final slot = useState(
      useMemoized(() {
        final current = ref.read(currentPresetProvider);

        return (current != null && current.bank == .user) ? current.number : 1;
      }),
    );

    final isSaving = useState(false);

    Future<void> save() async {
      isSaving.value = true;

      final ok = await savePreset(ref, slot.value, name.text);

      if (context.mounted) Navigator.pop(context, ok);
    }

    final isSaveEnabled = !isSaving.value && nameText.trim().isNotEmpty;

    // Block dismissal (back button / Escape) while a save is in flight, so the
    // WidgetRef passed into savePreset isn't disposed before savePreset's
    // post-await provider writes run. (Barrier taps are blocked by
    // barrierDismissible: false at the showDialog call site.)
    return PopScope(
      canPop: !isSaving.value,
      child: SonicDialog(
        maxWidth: 380,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            const Text('Save preset', style: AppText.dialogTitle),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                const Text('Preset name', style: AppText.inputLabel),
                Text('${nameText.length}/10', style: AppText.inputHint),
              ],
            ),
            const SizedBox(height: 6),
            SonicField(
              controller: name,
              autofocus: true,
              maxLength: 10,
              hintText: 'Name',
              style: AppText.input,
              onSubmitted: (_) {
                if (isSaveEnabled) save();
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Slot: ',
                  style: AppText.input.copyWith(
                    color: Palette.fieldText,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                SonicDropdown<int>(
                  value: slot.value,
                  width: 110,
                  items: [
                    for (var n = 1; n <= 50; n++)
                      (value: n, label: 'P${n.toString().padLeft(2, '0')}'),
                  ],
                  isEnabled: !isSaving.value,
                  onChanged: (v) => slot.value = v,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: .end,
              children: [
                SonicButton(
                  label: 'Cancel',
                  onPressed: isSaving.value
                      ? null
                      : () => Navigator.pop(context, false),
                ),
                const SizedBox(width: 10),
                SonicButton(
                  label: 'Save',
                  isAccent: true,
                  onPressed: isSaveEnabled ? save : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
