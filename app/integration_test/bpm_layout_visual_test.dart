// Renders the PresetFieldsPanel in both layouts side by side, in a real window,
// and holds it on screen to be screenshotted from outside. No device needed.
// Run: GDK_BACKEND=x11 flutter test integration_test/bpm_layout_visual_test.dart -d linux

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/theme/app_colors.dart';
import 'package:sonicmaster/theme/app_text.dart';
import 'package:sonicmaster/ui/preset_fields_panel.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BPM panel: side-by-side vs stacked', (tester) async {
    Widget labelled(String title, bool stacked) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppText.moduleTitle),
        const SizedBox(height: 8),
        PresetFieldsPanel(
          presetVolume: 60,
          presetBpm: 120,
          isLoading: false,
          topSpacer: 12,
          stacked: stacked,
          patchKnobKey: Key('k-$title'),
          onVolume: (_) {},
          onBpm: (_) {},
        ),
      ],
    );

    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF1A1A1A),
        builder: (context, _) => Container(
          color: Palette.background,
          padding: const EdgeInsets.all(32),
          child: DefaultTextStyle(
            style: AppText.moduleDescription,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelled('module 1 row', false),
                const SizedBox(width: 48),
                labelled('module wrapped', true),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Two panels × (Patch Vol + BPM).
    expect(find.text('BPM'), findsNWidgets(2));
    expect(find.text('PRESET VOL'), findsNWidgets(2));

    for (final _ in Iterable<int>.generate(60)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
}
