import 'package:flutter/widgets.dart';

import '../theme/app_text.dart';
import 'sonic_controls.dart';

/// Confirms discarding the current preset's unsaved (not-yet-persisted-to-slot)
/// edits before loading another preset. Returns true if the user chose Discard,
/// false on Cancel or dismissal. Styled like the other pop-ups (SonicDialog
/// plate + SonicButton actions).
Future<bool> showUnsavedChangesDialog(BuildContext context) async {
  final result = await showSonicDialog<bool>(
    context: context,
    builder: (context) => SonicDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          const Text('Discard unsaved changes?', style: AppText.dialogTitle),
          const SizedBox(height: 12),
          const Text(
            'The current preset has edits that are not saved to a slot. '
            'Loading another preset will discard them.',
            style: AppText.dialogBody,
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: .end,
            children: [
              SonicButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(width: 10),
              SonicButton(
                label: 'Discard',
                isAccent: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  return result ?? false;
}
