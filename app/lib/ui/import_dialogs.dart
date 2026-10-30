import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../protocol/nam_format.dart';
import '../state/preset_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';

/// Non-dismissible modal shown while an import (NAM/clone or IR) uploads. Reads
/// the shared status text and the import progress fraction, so it tracks both an
/// indeterminate phase (e.g. NAM conversion) and the chunked upload live.
class ImportProgressDialog extends ConsumerWidget {
  const ImportProgressDialog({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(presetLoadStatusProvider) ?? 'Preparing…';
    final progress = ref.watch(importProgressProvider);

    // The importer pops this route itself once the upload settles, so it must
    // outlive every user-initiated dismissal — otherwise that pop would close
    // the page underneath instead. barrierDismissible: false at the call site
    // blocks outside-taps and Escape; canPop: false covers the remaining routes
    // (back button / browser back).
    return PopScope(
      canPop: false,
      child: SonicDialog(
        maxWidth: 360,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Text(title, style: AppText.dialogTitle),
            const SizedBox(height: 20),
            Row(
              children: [
                const SonicSpinner(size: 22),
                const SizedBox(width: 14),
                Expanded(child: Text(status, style: AppText.dialogBody)),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 18),
              _ProgressBar(value: progress),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

/// A thin Material-free determinate bar: an accent fill in a recessed track.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final fraction = value.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        SonicRecess(
          radius: 5,
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: 8,
            child: FractionallySizedBox(
              alignment: .centerLeft,
              widthFactor: fraction,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Palette.accent,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: .centerRight,
          child: Text('${(fraction * 100).round()}%', style: AppText.inputHint),
        ),
      ],
    );
  }
}

/// Error dialog for a failed import. When [showSupportedFormats] is set it
/// appends the list of `.nam` formats the converter accepts — used when the
/// failure is a model-format mismatch (NAM/clone only).
class ImportErrorDialog extends StatelessWidget {
  const ImportErrorDialog({
    super.key,
    required this.title,
    required this.message,
    this.showSupportedFormats = false,
  });

  final String title;
  final String message;
  final bool showSupportedFormats;

  @override
  Widget build(BuildContext context) {
    return SonicDialog(
      maxWidth: 440,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Text(title, style: AppText.dialogTitle),
          const SizedBox(height: 12),
          Text(message, style: AppText.dialogBody),
          if (showSupportedFormats) ...[
            const SizedBox(height: 18),
            Text('SUPPORTED FORMATS', style: AppText.inputLabel),
            const SizedBox(height: 8),
            for (final format in supportedNamFormats)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: .start,
                  children: [
                    Text('•  ', style: AppText.dialogBody),
                    Expanded(child: Text(format, style: AppText.dialogBody)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: .end,
            children: [
              SonicButton(
                label: 'OK',
                isAccent: true,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
