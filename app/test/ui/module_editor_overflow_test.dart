import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/decoded_preset_state.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/module_editor.dart';
import 'package:sonicmaster/ui/preset_fields_panel.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

import '../support/test_assets.dart';

/// Guards the two work-panels (Preset Vol/BPM + module editor) against overflow
/// at the app's MINIMUM width. `PresetBrowserPage` never lays out below
/// `_minAppWidth` (960) — narrower viewports scroll horizontally instead — so the
/// tightest real case is that minimum. There the work-area content is
/// 960 − rail(244) − padding(24) = 692, which the two-panel Row fills. This pins
/// that the FOOT SWITCH bar (None/FS1/FS2) and the module Wrap both fit at that
/// width (a regression that shrank the min, widened the rail/preset panel, or
/// grew the bar would resurface an overflow here).
///
/// Mirrors the real structure: `IntrinsicHeight` + `Row(stretch)` with a
/// fixed-width Preset panel beside an `Expanded` editor. `Expanded` (not a fixed
/// inner `SizedBox`) keeps it faithful — the intrinsic pass and the real layout
/// give the editor the SAME width, as in the app.
void main() {
  final assets = loadTestDataAssets();

  DecodedPresetState state() => const DecodedPresetState(
    isCloneMode: false,
    presetVolume: 44,
    presetBpm: 120,
    moduleStates: {},
    chainOrder: [],
    footswitchFs1Mask: 0,
    footswitchFs2Mask: 0,
  );

  Future<void> pumpTwoPanels(WidgetTester tester, double width) async {
    final container = ProviderContainer(
      overrides: [
        dataAssetsProvider.overrideWith((_) => assets),
        currentSelectedEffectsProvider.overrideWith((_) => {0: 1}), // NR = Gate
        currentParametersProvider.overrideWith(
          (_) => {
            0: {0: 20},
          },
        ),
        currentPresetStateProvider.overrideWith((_) => state()),
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
                        stacked: true,
                        patchKnobKey: const ValueKey('patch'),
                        onVolume: (_) {},
                        onBpm: (_) {},
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 212),
                          child: const SonicSurface(
                            padding: EdgeInsets.zero,
                            child: ModuleEditor(0),
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
    );
  }

  // A single pump then takeException: an overflow is reported once per frame, so
  // one drain per fresh pumpWidget reliably surfaces it (a multi-pump loop would
  // hit the framework's repeat-overflow throttling and miss it).
  void expectNoOverflow(WidgetTester tester) {
    final e = tester.takeException();

    expect(
      e == null || !e.toString().contains('overflowed'),
      isTrue,
      reason: e.toString(),
    );
  }

  // 692 = the work-area content width at the app's minimum window (960).
  testWidgets('two-panel layout does not overflow at the 960 minimum', (
    tester,
  ) async {
    await pumpTwoPanels(tester, 692);
    expectNoOverflow(tester);
  });

  testWidgets('two-panel layout does not overflow above the minimum', (
    tester,
  ) async {
    await pumpTwoPanels(tester, 820);
    expectNoOverflow(tester);
  });
}
