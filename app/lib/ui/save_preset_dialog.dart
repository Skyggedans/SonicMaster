import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../state/names_providers.dart';
import '../state/preset_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';
import 'sonic_field.dart';
import 'sonic_metrics.dart';

/// Presents [SavePresetDialog]. Like every other pop-up in the app it dismisses
/// on an outside tap (the in-flight save is guarded by the dialog's own
/// PopScope, not by a non-dismissible barrier). Resolves to true when the save
/// ACKed, false on Cancel, null when dismissed.
Future<bool?> showSavePresetDialog(BuildContext context) {
  return showSonicDialog<bool>(
    context: context,
    builder: (_) => const SavePresetDialog(),
  );
}

/// Name + target-slot dialog for saving the current edits to flash (`040A`).
class SavePresetDialog extends HookConsumerWidget {
  const SavePresetDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read once: the dialog seeds its fields from the preset that was loaded
    // when it opened, and must not re-seed them under the user mid-edit.
    final current = useMemoized(() => ref.read(currentPresetProvider));

    // Prefill the loaded preset's decoded *name* so a re-save doesn't force the
    // user to retype it. Never the slot *label* (e.g. "P05"/"F03") — that is not
    // a stored name, and writing it to flash would be misleading. Empty when the
    // name dump hasn't been decoded yet.
    final name = useTextEditingController(
      text: current == null ? '' : ref.read(presetNamesProvider)[current] ?? '',
    );

    final nameText = useValueListenable(name).text;

    final slot = useState(
      (current != null && current.bank == .user) ? current.number : 1,
    );

    final isSaving = useState(false);

    Future<void> save() async {
      isSaving.value = true;

      final ok = await savePreset(ref, slot.value, name.text);

      if (context.mounted) Navigator.pop(context, ok);
    }

    final isSaveEnabled = !isSaving.value && nameText.trim().isNotEmpty;
    final isCompact = SonicMetrics.of(context).isCompact;

    // Block dismissal while a save is in flight, so the WidgetRef passed into
    // savePreset isn't disposed before savePreset's post-await provider writes
    // run. This covers every route out: back button, Escape and outside-taps
    // all go through Navigator.maybePop, which honours canPop.
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
                // Compact with the soft keyboard up: Done only closes the
                // keyboard (it has already unfocused the field), revealing the
                // Slot picker below; saving stays an explicit tap on Save.
                // A hardware Enter (no inset) and the regular layout still
                // save at once.
                if (isCompact && MediaQuery.viewInsetsOf(context).bottom > 0) {
                  return;
                }

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
