import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/decoded_preset_state.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/module_editor.dart';
import 'package:sonicmaster/ui/preset_fields_panel.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

import '../support/fonts.dart';
import '../support/test_assets.dart';
import '../support/view_helpers.dart';

/// The compact twin of module_editor_overflow_test: the two work panels
/// (IntrinsicHeight + Row(stretch), a fixed Preset panel beside an Expanded
/// editor) at real compact work widths, with Oswald. 836 / 764 / 624 are
/// 852 / 780 / 640-wide viewports minus the 2 x 8 work padding; 624 is the
/// narrowest, since the app never lays out below the 640 compact minimum.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final assets = loadTestDataAssets();

  setUpAll(loadOswald);

  Future<void> pumpTwoPanels(
    WidgetTester tester, {
    required double width,
    required bool isStacked,
    required int moduleId,
    required int fxId,
    required Map<int, num> params,
    required bool isCloneMode,
    required Map<int, String> userNames,
  }) async {
    final container = ProviderContainer(
      overrides: [
        dataAssetsProvider.overrideWith((_) => assets),
        currentSelectedEffectsProvider.overrideWith((_) => {moduleId: fxId}),
        currentParametersProvider.overrideWith((_) => {moduleId: params}),
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
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Directionality(
          textDirection: .ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: SonicMetricsScope(
              metrics: SonicMetrics.compact,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: .stretch,
                      children: [
                        PresetFieldsPanel(
                          presetVolume: 44,
                          presetBpm: 120,
                          isLoading: false,
                          topSpacer: 12,
                          stacked: isStacked,
                          patchKnobKey: const ValueKey('patch'),
                          onVolume: (_) {},
                          onBpm: (_) {},
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: SonicMetrics.compact.minPanelHeight,
                            ),
                            child: SonicSurface(
                              padding: EdgeInsets.zero,
                              child: ModuleEditor(moduleId),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // (name, moduleId, fxId, params, isCloneMode, hasLongName)
  const cases = [
    ('NR Gate', 0, 1, <int, num>{0: 20}, false, false),
    ('AMP Brit 45 (6 knobs)', 3, 306, <int, num>{}, false, false),
    ('AMP Brit 50JP (7 knobs)', 3, 307, <int, num>{}, false, false),
    ('Clone User Profile 1', 9, 901, <int, num>{}, true, false),
    ('Clone, 15-char name', 9, 901, <int, num>{}, true, true),
    ('IR User IR 1', 4, 416, <int, num>{}, false, false),
    ('DLY Sweep + tap tempo', 7, 708, <int, num>{1: 500, 6: 0}, false, false),
    ('FX1 Auto Wah, synced', 1, 104, <int, num>{1: 4, 6: 1}, false, false),
  ];

  for (final width in const [836.0, 764.0, 624.0]) {
    for (final (name, moduleId, fxId, params, isCloneMode, hasLongName)
        in cases) {
      for (final isStacked in const [false, true]) {
        final layout = isStacked ? 'stacked' : 'side by side';

        testWidgets('$name at ${width.toInt()}, $layout', (tester) async {
          await pumpTwoPanels(
            tester,
            width: width,
            isStacked: isStacked,
            moduleId: moduleId,
            fxId: fxId,
            params: params,
            isCloneMode: isCloneMode,
            userNames: hasLongName
                ? const {901: 'WWWWWWWWWWWWWWW'}
                : const <int, String>{},
          );

          expectNoOverflow(tester);
          expect(tester.getSize(find.byType(PresetFieldsPanel)).width, 194);

          // Cancels the DLY beat timer; harmless for the others.
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
