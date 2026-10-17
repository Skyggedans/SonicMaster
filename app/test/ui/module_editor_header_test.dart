import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/decoded_preset_state.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/module_editor.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

import '../support/fonts.dart';
import '../support/test_assets.dart';
import '../support/view_helpers.dart';

/// The editor header: [title][effect, centred][on/off]. A user-named clone
/// holds up to 15 characters (CloUploadFrame.nameMaxChars), which used to push
/// the header past the regular editor's 324 px at the 960 minimum
/// (692 - 360 - 8). A name that fits must sit exactly where it always did.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final assets = loadTestDataAssets();

  setUpAll(loadOswald);

  Future<void> pumpEditor(
    WidgetTester tester, {
    required int moduleId,
    required int fxId,
    bool isCloneMode = false,
    Map<int, String> userNames = const {},
  }) async {
    final container = ProviderContainer(
      overrides: [
        dataAssetsProvider.overrideWith((_) => assets),
        currentSelectedEffectsProvider.overrideWith((_) => {moduleId: fxId}),
        currentPresetStateProvider.overrideWith(
          (_) => DecodedPresetState(
            isCloneMode: isCloneMode,
            presetVolume: 44,
            presetBpm: 120,
            moduleStates: const {},
            chainOrder: const [],
          ),
        ),
        userNamesProvider.overrideWith((_) => userNames),
      ],
    );

    addTearDown(container.dispose);
    await container.read(dataAssetsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Directionality(
          textDirection: .ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 324,
                child: SingleChildScrollView(
                  child: SonicSurface(
                    padding: EdgeInsets.zero,
                    child: ModuleEditor(moduleId),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a 15-character clone name ellipsizes in the 324-px header', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      moduleId: 9,
      fxId: 901,
      isCloneMode: true,
      userNames: const {901: 'WWWWWWWWWWWWWWW'},
    );

    expectNoOverflow(tester);

    final title = tester.getRect(find.text('AMP'));
    final effect = tester.getRect(find.byType(SonicDropdown<int>).first);
    final toggle = tester.getRect(find.byType(SonicToggle).first);

    expect(effect.left, greaterThanOrEqualTo(title.right));
    expect(effect.right, lessThanOrEqualTo(toggle.left));
  });

  // A pin: true before and after the change. Spacer / effect / Spacer and
  // Expanded(Center(effect)) both put a fitting effect at its natural width,
  // centred in the room between the title and the toggle.
  for (final (moduleId, fxId, title, isDropdown) in const [
    (0, 1, 'NR', false), // NR has one effect: the static 'Gate' label
    (3, 307, 'AMP', true), // AMP: the effect dropdown
  ]) {
    testWidgets('$title: an effect that fits sits midway, at natural width', (
      tester,
    ) async {
      await pumpEditor(tester, moduleId: moduleId, fxId: fxId);

      final titleRect = tester.getRect(find.text(title));
      final toggle = tester.getRect(find.byType(SonicToggle).first);
      final effect = tester.getRect(
        isDropdown
            ? find.byType(SonicDropdown<int>).first
            : find.text(assets.effects.byId(fxId)!.name),
      );

      expect(
        effect.center.dx,
        closeTo((titleRect.right + toggle.left) / 2, 0.01),
      );
      expect(effect.center.dy, closeTo(toggle.center.dy, 0.01));
      expect(effect.width, lessThan(toggle.left - titleRect.right));
    });
  }
}
