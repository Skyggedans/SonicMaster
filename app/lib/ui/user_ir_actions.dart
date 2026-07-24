import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../protocol/ir_upload_frame.dart';
import '../state/ir_upload.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';
import 'sonic_field.dart';

/// Load / Rename / Clear actions for a User-IR slot (module 4, fxId 416–420),
/// rendered as one panel cell. Slot is 0-based (0 = User IR 1 … 4 = User IR 5).
class UserIrActions extends ConsumerWidget {
  const UserIrActions({
    super.key,
    required this.slot,
    required this.isEnabled,
    required this.currentName,
  });

  final int slot;
  final bool isEnabled;
  final String currentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PanelCell(
      label: 'IR File',
      control: Row(
        mainAxisSize: .min,
        children: [
          SonicButton(
            label: 'Load…',
            height: 40,
            minWidth: 72,
            onPressed: isEnabled ? () => uploadIrFromFile(ref, slot) : null,
          ),
          const SizedBox(width: 4),
          SonicButton(
            label: 'Name…',
            height: 40,
            minWidth: 72,
            onPressed: isEnabled ? () => _rename(context, ref) : null,
          ),
          const SizedBox(width: 4),
          SonicButton(
            label: 'Clear',
            height: 40,
            minWidth: 72,
            onPressed: isEnabled ? () => _clear(context, ref) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showSonicDialog<String>(
      context: context,
      builder: (_) => _RenameIrDialog(slot: slot, initial: currentName),
    );

    if (name != null && name.isNotEmpty) {
      await renameIrSlot(ref, slot, name);
    }
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final isConfirmed = await showSonicDialog<bool>(
      context: context,
      builder: (dialogContext) => SonicDialog(
        maxWidth: 360,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Text('Clear User IR ${slot + 1}?', style: AppText.dialogTitle),
            const SizedBox(height: 12),
            const Text(
              'This erases the loaded impulse response.',
              style: AppText.dialogBody,
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: .end,
              children: [
                SonicButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(dialogContext, false),
                ),
                const SizedBox(width: 10),
                SonicButton(
                  label: 'Clear',
                  isAccent: true,
                  onPressed: () => Navigator.pop(dialogContext, true),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (isConfirmed ?? false) {
      await clearIrSlot(ref, slot);
    }
  }
}

/// Sonic name-entry dialog for a slot rename, mirroring the save-preset dialog.
/// A HookWidget owns the text controller; pops the trimmed name, or null.
class _RenameIrDialog extends HookWidget {
  const _RenameIrDialog({required this.slot, required this.initial});

  final int slot;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final name = useTextEditingController(text: initial);
    final nameText = useValueListenable(name).text;
    final isRenameEnabled = nameText.trim().isNotEmpty;

    void submit() {
      if (isRenameEnabled) Navigator.pop(context, name.text.trim());
    }

    return SonicDialog(
      maxWidth: 380,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Text('Rename User IR ${slot + 1}', style: AppText.dialogTitle),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: .spaceBetween,
            children: [
              const Text('Name', style: AppText.inputLabel),
              Text(
                '${nameText.length}/${IrUploadFrame.nameMaxChars}',
                style: AppText.inputHint,
              ),
            ],
          ),
          const SizedBox(height: 6),
          SonicField(
            controller: name,
            autofocus: true,
            maxLength: IrUploadFrame.nameMaxChars,
            hintText: 'Name',
            style: AppText.input,
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: .end,
            children: [
              SonicButton(
                label: 'Cancel',
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 10),
              SonicButton(
                label: 'Rename',
                isAccent: true,
                onPressed: isRenameEnabled ? submit : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
