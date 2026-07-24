import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../protocol/clo_upload_frame.dart';
import '../protocol/nam_format.dart';
import '../state/clone_upload.dart';
import '../state/preset_providers.dart';
import '../theme/app_text.dart';
import 'clone_import_dialogs.dart';
import 'sonic_controls.dart';
import 'sonic_field.dart';

/// Load / Rename / Clear actions for a User-Profile clone slot (module 9, fxId
/// 901–905), rendered as one panel cell. Load picks a `.nam`, converts it
/// natively to a `.clo`, and uploads it. Slot is 0-based (0 = User Profile 1 …
/// 4 = User Profile 5).
class UserProfileActions extends ConsumerWidget {
  const UserProfileActions({
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
      label: 'NAM Profile',
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

  /// Picks a `.nam`, validates its format, then converts + uploads it behind a
  /// progress modal. Format mismatches and conversion/upload failures surface as
  /// an error dialog (with the supported-formats list for format problems).
  Future<void> _load(BuildContext context, WidgetRef ref) async {
    if (ref.read(presetLoadingProvider)) return;

    final String namJson;
    final String fileName;

    try {
      final picked = await pickNamForClone(slot);

      if (picked == null) return;

      fileName = picked.name;
      namJson = validateNam(picked.namJson);
    } on UnsupportedNamFormat catch (e) {
      if (context.mounted) {
        await _showError(
          context,
          'Unsupported model format',
          'This .nam is a "${e.architecture}" model, which the clone converter '
              "can't convert.",
          showSupportedFormats: true,
        );
      }

      return;
    } catch (e) {
      if (context.mounted) {
        await _showError(context, 'NAM load failed', '$e');
      }

      return;
    }

    if (!context.mounted) return;

    unawaited(
      showSonicDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CloneImportProgressDialog(slot: slot),
      ),
    );

    CloneImportException? failure;

    try {
      await convertAndUploadClone(
        ref,
        slot: slot,
        namJson: namJson,
        fileName: fileName,
      );
    } on CloneImportException catch (e) {
      failure = e;
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (failure != null && context.mounted) {
      await _showError(
        context,
        'Import failed',
        failure.message,
        showSupportedFormats: failure.isFormatError,
      );
    }
  }

  Future<void> _showError(
    BuildContext context,
    String title,
    String message, {
    bool showSupportedFormats = false,
  }) {
    return showSonicDialog<void>(
      context: context,
      builder: (_) => CloneImportErrorDialog(
        title: title,
        message: message,
        showSupportedFormats: showSupportedFormats,
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showSonicDialog<String>(
      context: context,
      builder: (_) => _RenameCloneDialog(slot: slot, initial: currentName),
    );

    if (name != null && name.isNotEmpty) {
      await renameCloneSlot(ref, slot, name);
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
            Text('Clear User Profile ${slot + 1}?', style: AppText.dialogTitle),
            const SizedBox(height: 12),
            const Text(
              'This erases the loaded clone profile.',
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
      await clearCloneSlot(ref, slot);
    }
  }
}

/// Sonic name-entry dialog for a clone rename. A HookWidget owns the text
/// controller; pops the trimmed name, or null.
class _RenameCloneDialog extends HookWidget {
  const _RenameCloneDialog({required this.slot, required this.initial});

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
          Text('Rename User Profile ${slot + 1}', style: AppText.dialogTitle),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: .spaceBetween,
            children: [
              const Text('Name', style: AppText.inputLabel),
              Text(
                '${nameText.length}/${CloUploadFrame.nameMaxChars}',
                style: AppText.inputHint,
              ),
            ],
          ),
          const SizedBox(height: 6),
          SonicField(
            controller: name,
            autofocus: true,
            maxLength: CloUploadFrame.nameMaxChars,
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
