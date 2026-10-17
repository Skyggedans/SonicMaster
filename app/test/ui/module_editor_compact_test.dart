import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/decoded_preset_state.dart';
import 'package:sonicmaster/model/footswitch_assignment.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/module_editor.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

import '../support/fonts.dart';
import '../support/test_assets.dart';
import '../support/view_helpers.dart';

/// The module editor at compact density: 72-px knobs, a 40-px header, 32-px
/// controls, slimmer foot-switch segments and no description. Editor widths are
/// those of real compact work areas (viewport - 2 x 8 padding - 194 Preset
/// panel - 8 gap): 634 at 852 wide, 548 at 780, 422 at the 640 minimum.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final assets = loadTestDataAssets();

  setUpAll(loadOswald);

  Future<void> pumpEditor(
    WidgetTester tester, {
    required int moduleId,
    required int fxId,
    double width = 634,
    SonicMetrics metrics = SonicMetrics.compact,
    Map<int, num> params = const {},
    bool isCloneMode = false,
    Map<int, String> userNames = const {},
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Directionality(
          textDirection: .ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: SonicMetricsScope(
              metrics: metrics,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
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
      ),
    );
  }

  // The header ends where the control Wrap begins.
  double headerHeight(WidgetTester tester) =>
      tester.getTopLeft(find.byType(Wrap).first).dy -
      tester.getTopLeft(find.byType(ModuleEditor)).dy;

  Iterable<Size> dials(WidgetTester tester) =>
      find.byKey(const Key('knob')).evaluate().map((element) => element.size!);

  Finder inCell(String label, Type type) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PanelCell && w.label == label),
    matching: find.byType(type),
  );

  for (final (metrics, dial, header) in const [
    (SonicMetrics.compact, 72.0, 40.0), // 4 + 32-px dropdown + 4
    (SonicMetrics.regular, 120.0, 56.0), // 12 + 40-px dropdown + 4
  ]) {
    final mode = metrics.isCompact ? 'compact' : 'regular';

    testWidgets(
      '$mode: ${dial.toInt()}-px knobs under a ${header.toInt()}-px header',
      (tester) async {
        await pumpEditor(tester, moduleId: 3, fxId: 307, metrics: metrics);

        expect(dials(tester), everyElement(Size.square(dial)));
        expect(headerHeight(tester), header);
        expect(
          tester.getSize(find.byType(SonicDropdown<int>).first).height,
          metrics.editorControlHeight,
        );
        expect(
          find.text(assets.effects.byId(307)!.descriptionEn),
          metrics.isCompact ? findsNothing : findsOneWidget,
        );
      },
    );
  }

  testWidgets('compact: 32-px panel controls and slimmer FS segments', (
    tester,
  ) async {
    await pumpEditor(tester, moduleId: 9, fxId: 901, isCloneMode: true);

    final footswitch = find.byType(SonicSegmented<FootswitchAssignment>);

    expect(tester.getSize(inCell('Clone Mode', SonicToggle)).height, 32);
    expect(
      tester.getSize(find.widgetWithText(SonicButton, 'Load…')).height,
      32,
    );
    expect(
      tester
          .widget<SonicSegmented<FootswitchAssignment>>(footswitch)
          .segmentPadding,
      10,
    );
    // NONE / FS1 / FS2 at 10 px a side, in a 4-px cell padding: 44 px
    // narrower than the regular 196.1-px cell.
    expect(
      tester
          .getSize(
            find.ancestor(of: footswitch, matching: find.byType(PanelCell)),
          )
          .width,
      closeTo(152.1, 0.1),
    );
  });

  testWidgets('compact: the synced Rate division dropdown is 32 tall', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      moduleId: 1,
      fxId: 104,
      params: const {1: 4, 6: 1},
    );

    expect(tester.getSize(inCell('Rate', SonicDropdown<int>)).height, 32);
  });

  testWidgets('compact: the tap-tempo division dropdown is 32 tall', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      moduleId: 7,
      fxId: 708,
      params: const {1: 500, 6: 0},
    );

    expect(tester.getSize(find.byType(SonicDropdown<double>)).height, 32);
    expect(tester.getSize(find.widgetWithText(SonicButton, 'TAP')).height, 44);

    // Cancels TapTempoControl's beat timer.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // The other non-knob controls follow the metrics' control height too: a
  // toggle parameter, a select parameter and the IR file buttons. (The Clone
  // Mode toggle, the clone buttons and the division dropdowns are pinned
  // above.)
  for (final (metrics, height) in const [
    (SonicMetrics.compact, 32.0),
    (SonicMetrics.regular, 40.0),
  ]) {
    final mode = metrics.isCompact ? 'compact' : 'regular';
    final px = height.toInt();

    testWidgets('$mode: a toggle parameter is $px tall', (tester) async {
      // FX1 Auto Wah: its Sync toggle.
      await pumpEditor(tester, moduleId: 1, fxId: 104, metrics: metrics);

      expect(tester.getSize(inCell('Sync', SonicToggle)).height, height);
    });

    testWidgets('$mode: a select parameter dropdown is $px tall', (
      tester,
    ) async {
      // FX1 Touch Wah: its Mode select (Guitar / Bass).
      await pumpEditor(tester, moduleId: 1, fxId: 103, metrics: metrics);

      expect(tester.getSize(inCell('Mode', SonicDropdown<int>)).height, height);
    });

    testWidgets('$mode: the IR file buttons are $px tall', (tester) async {
      await pumpEditor(tester, moduleId: 4, fxId: 416, metrics: metrics);

      for (final label in const ['Load…', 'Name…', 'Clear']) {
        expect(
          tester.getSize(find.widgetWithText(SonicButton, label)).height,
          height,
          reason: label,
        );
      }
    });
  }

  // (name, moduleId, fxId, params, isCloneMode)
  const editors = [
    ('AMP Brit 50JP', 3, 307, <int, num>{}, false),
    ('Clone User Profile 1', 9, 901, <int, num>{}, true),
    ('IR User IR 1', 4, 416, <int, num>{}, false),
    ('DLY Sweep + tap tempo', 7, 708, <int, num>{1: 500, 6: 0}, false),
    ('FX1 Auto Wah, synced', 1, 104, <int, num>{1: 4, 6: 1}, false),
  ];

  group('no overflow at compact editor widths', () {
    for (final width in const [634.0, 548.0, 422.0]) {
      for (final (name, moduleId, fxId, params, isCloneMode) in editors) {
        testWidgets('$name at ${width.toInt()}', (tester) async {
          await pumpEditor(
            tester,
            moduleId: moduleId,
            fxId: fxId,
            width: width,
            params: params,
            isCloneMode: isCloneMode,
          );

          expectNoOverflow(tester);
          expect(dials(tester), everyElement(const Size.square(72)));

          // Cancels the DLY beat timer; harmless for the others.
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }

      testWidgets('a 15-char clone name at ${width.toInt()}', (tester) async {
        await pumpEditor(
          tester,
          moduleId: 9,
          fxId: 901,
          width: width,
          isCloneMode: true,
          userNames: const {901: 'WWWWWWWWWWWWWWW'},
        );

        expectNoOverflow(tester);
      });
    }
  });
}
