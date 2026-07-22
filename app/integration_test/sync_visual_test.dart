// Renders FX1 holding Auto Wah with Sync engaged, in a real window, and holds
// it on screen so it can be looked at (screenshot from outside with
// `import -window SonicMaster`). Drives the widget tree through Flutter's own
// pipeline — this machine's compositor (GNOME Wayland) refuses synthetic
// pointer motion, so xdotool/ydotool cannot drive the GUI at all.
//
// Run: flutter test integration_test/sync_visual_test.dart -d linux
//
// No device needed: the providers are overridden, so this is purely the render.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/theme/app_text.dart';
import 'package:sonicmaster/ui/module_editor.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FX1 / Auto Wah with Sync on renders the division dropdown', (
    tester,
  ) async {
    final assets = await DataAssets.load();

    final container = ProviderContainer(
      overrides: [
        dataAssetsProvider.overrideWith((_) => Future.value(assets)),
        currentSelectedEffectsProvider.overrideWith((_) => {1: 104}),
        // Sync (alg 6) on; Rate (alg 1) holding division index 4 = "1/4" —
        // exactly what the pedal itself writes when the gate engages.
        currentParametersProvider.overrideWith(
          (_) => {
            1: {0: 50, 1: 4, 2: 50, 3: 25, 4: 70, 5: 60, 6: 1},
          },
        ),
      ],
    );

    addTearDown(container.dispose);
    await container.read(dataAssetsProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: WidgetsApp(
          color: const Color(0xFF1A1A1A),
          builder: (context, _) => Container(
            color: const Color(0xFF262626),
            padding: const EdgeInsets.all(24),
            child: DefaultTextStyle(
              style: AppText.moduleDescription,
              child: const Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(child: ModuleEditor(1)),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // The whole point: the Hz knob is gone, a division dropdown stands in.
    expect(
      find.byWidgetPredicate((w) => w is SonicDropdown<int> && w.width == 112),
      findsOneWidget,
    );

    // Hold it on screen long enough to capture from outside.
    for (final _ in Iterable<int>.generate(60)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
}
