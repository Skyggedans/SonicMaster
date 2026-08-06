import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../protocol/ir_upload_frame.dart';
import '../state/import_exception.dart';
import '../state/ir_upload.dart';
import '../state/preset_providers.dart';
import '../theme/app_text.dart';
import 'import_dialogs.dart';
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
            onPressed: isEnabled ? () => _load(context, ref) : null,
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

  /// Picks a WAV, then uploads it into the slot behind a non-dismissible progress
  /// modal (mirrors the clone Load flow). Upload failures surface as an error
  /// dialog once the modal is dismissed.
  Future<void> _load(BuildContext context, WidgetRef ref) async {
    if (ref.read(presetLoadingProvider)) return;

    final ({Uint8List bytes, String name})? picked;

    try {
      picked = await pickIrForUpload(slot);
    } catch (e) {
      if (context.mounted) {
        await _showError(context, 'IR load failed', '$e');
      }

      return;
    }

    if (picked == null) return;

    if (!context.mounted) return;

    unawaited(
      showSonicDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            ImportProgressDialog(title: 'Importing to User IR ${slot + 1}'),
      ),
    );

    ImportException? failure;

    try {
      await uploadIr(
        ref,
        slot: slot,
        bytes: picked.bytes,
        fileName: picked.name,
      );
    } on ImportException catch (e) {
      failure = e;
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (failure != null && context.mounted) {
      await _showError(context, 'IR import failed', failure.message);
    }
  }

  Future<void> _showError(BuildContext context, String title, String message) {
    return showSonicDialog<void>(
      context: context,
      builder: (_) => ImportErrorDialog(title: title, message: message),
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
