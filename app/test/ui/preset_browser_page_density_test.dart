import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/edit_providers.dart';
import 'package:sonicmaster/ui/chain_view.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/module_editor.dart';
import 'package:sonicmaster/ui/preset_fields_panel.dart';
import 'package:sonicmaster/ui/preset_rail.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

import '../support/page_harness.dart';
import '../support/view_helpers.dart';

/// The work area of the whole page per density: regular keeps today's
/// numbers; compact fits a phone (one chain row, the first knob row above the
/// fold at 360 px and up, nothing overflowing at any phone size).
///
/// Fake time: zero-length pumps plus two 50-ms ones, far below the connected
/// heartbeat's 2 s; pages with the DLY tap tempo are unmounted at the end (its
/// beat timer).
void main() {
  /// The page with [moduleId]'s editor open on [fxId].
  Future<ProviderContainer> pumpEditorPage(
    WidgetTester tester, {
    required Size size,
    int moduleId = 0,
    int fxId = 1,
    Map<int, num> params = const {},
    bool isCloneMode = false,
  }) => pumpPage(
    tester,
    size: size,
    state: loadedPresetState.copyWith(isCloneMode: isCloneMode),
    selectedEffects: {moduleId: fxId},
    parameters: {moduleId: params},
    overrides: [selectedModuleProvider.overrideWith((_) => moduleId)],
  );

  Finder inEditor(Finder finder) =>
      find.descendant(of: find.byType(ModuleEditor), matching: finder);

  // The editor's plate: the SonicSurface right around ModuleEditor.
  Finder editorSurface() => find
      .ancestor(
        of: find.byType(ModuleEditor),
        matching: find.byType(SonicSurface),
      )
      .first;

  double gap(WidgetTester tester) =>
      tester.getTopLeft(find.byType(PresetFieldsPanel)).dy -
      tester.getBottomLeft(find.byType(ChainView)).dy;

  Iterable<double> cardWidths() =>
      find.byType(ModuleCard).evaluate().map((element) => element.size!.width);

  // How far apart the chain cards' top edges are: ~0 on one row (the amp
  // block's cards sit inside its 4-px padding), ~110 once a second row starts.
  double cardTopSpread(WidgetTester tester) {
    final tops = find
        .byType(ModuleCard)
        .evaluate()
        .map((element) => tester.getTopLeft(find.byWidget(element.widget)).dy)
        .toList();

    return tops.reduce(math.max) - tops.reduce(math.min);
  }

  String label(Size size) => '${size.width.toInt()}x${size.height.toInt()}';

  const heavyEditors = [
    ('AMP Brit 50JP', 3, 307, <int, num>{}, false),
    ('Clone User Profile 1', 9, 901, <int, num>{}, true),
    ('DLY Sweep + tap tempo', 7, 708, <int, num>{1: 500, 6: 0}, false),
  ];

  group('regular keeps the pre-compact work area', () {
    for (final size in const [Size(1280, 800), Size(960, 640)]) {
      testWidgets('${label(size)}: padding 12, gap 34, 360 panel, 120 dials', (
        tester,
      ) async {
        await pumpPage(tester, size: size);

        expect(tester.getTopLeft(find.byType(ChainView)).dx, railWidth + 12);
        expect(gap(tester), 34);
        expect(tester.getSize(find.byType(PresetFieldsPanel)).width, 360);
        expect(
          tester.getSize(inEditor(find.byKey(const Key('knob'))).first),
          const Size.square(120),
        );
        expect(cardWidths(), everyElement(96));
      });

      testWidgets('${label(size)}: an empty editor keeps the 212 minimum', (
        tester,
      ) async {
        await pumpPage(tester, size: size, selectedEffects: const {});

        expect(tester.getSize(editorSurface()).height, 212);
        expect(tester.getSize(find.byType(PresetFieldsPanel)).height, 212);
      });
    }
  });

  group('compact', () {
    testWidgets('852x393: padding 8, gap 8, 194 panel, 72 dials, one row', (
      tester,
    ) async {
      // A two-row editor: the content is taller than the work area, so it is
      // top-aligned and the chain starts right under the work padding. NR is
      // on FS1; its badge overhangs the card corner and must stay inside the
      // work area's scroll viewport, which starts under the 48-px title bar.
      await pumpPage(
        tester,
        size: const Size(852, 393),
        state: loadedPresetState.withFootswitchMasks(fs1Mask: 1, fs2Mask: 0),
        selectedEffects: const {3: 307},
        parameters: const {3: {}},
        overrides: [selectedModuleProvider.overrideWith((_) => 3)],
      );

      const metrics = SonicMetrics.compact;

      final chain = tester.getTopLeft(find.byType(ChainView));
      final badge = find
          .ancestor(
            of: find.descendant(
              of: find.byType(ChainView),
              matching: find.text('FS1'),
            ),
            matching: find.byType(Container),
          )
          .first;

      expect(chain, Offset(8, metrics.topBarHeight + 8));
      expect(gap(tester), 8);
      expect(tester.getSize(find.byType(PresetFieldsPanel)).width, 194);
      expect(
        tester.getSize(inEditor(find.byKey(const Key('knob'))).first),
        const Size.square(72),
      );
      expect(cardWidths(), everyElement(77));
      expect(cardTopSpread(tester), lessThanOrEqualTo(4));
      expect(
        tester.getRect(badge).top,
        greaterThanOrEqualTo(metrics.topBarHeight),
      );
    });

    testWidgets('852x393: an empty editor keeps the 142 minimum', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(852, 393),
        selectedEffects: const {},
      );

      expect(tester.getSize(editorSurface()).height, 142);
      expect(tester.getSize(find.byType(PresetFieldsPanel)).height, 142);
    });

    // The D5 target: at 360 px and up (fullscreen / installed app) the first
    // row of a two- or three-row editor is on screen without scrolling: bar 48
    // + padding 8 + chain row 111 (the amp block holding the selected card) +
    // gap 8 + border 1 + header 40 + one 123-px cell = 339.
    for (final size in const [Size(852, 393), Size(780, 360), Size(640, 360)]) {
      testWidgets('${label(size)}: the first knob row is fully on screen', (
        tester,
      ) async {
        await pumpEditorPage(tester, size: size, moduleId: 3, fxId: 307);

        const metrics = SonicMetrics.compact;

        final knob = tester.getRect(inEditor(find.byType(KnobControl)).first);
        final chain = tester.getSize(find.byType(ChainView)).height;

        expect(
          knob.bottom,
          metrics.topBarHeight +
              metrics.workPadding +
              chain +
              metrics.chainPanelsGap +
              1 + // the editor plate's border
              metrics.editorHeaderPadding.vertical +
              metrics.editorControlHeight +
              knob.height,
        );
        expect(knob.bottom, lessThanOrEqualTo(size.height));
      });
    }

    for (final size in const [Size(740, 280), Size(640, 300)]) {
      testWidgets(
        '${label(size)}: a browser tab height scrolls, nothing overflows',
        (tester) async {
          await pumpEditorPage(tester, size: size, moduleId: 3, fxId: 307);

          expectNoOverflow(tester);

          final position = tester
              .state<ScrollableState>(
                find
                    .ancestor(
                      of: find.byType(ChainView),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;

          expect(position.maxScrollExtent, greaterThan(0));

          position.jumpTo(position.maxScrollExtent);
          await tester.pump();

          expect(
            tester.getRect(editorSurface()).bottom,
            lessThanOrEqualTo(size.height),
          );
        },
      );
    }

    for (final size in const [Size(852, 393), Size(640, 360)]) {
      for (final (name, moduleId, fxId, params, isCloneMode) in heavyEditors) {
        testWidgets('${label(size)}: $name does not overflow', (tester) async {
          await pumpEditorPage(
            tester,
            size: size,
            moduleId: moduleId,
            fxId: fxId,
            params: params,
            isCloneMode: isCloneMode,
          );

          expectNoOverflow(tester);
          expect(inEditor(find.byType(KnobControl)), findsWidgets);

          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }

    // The load-bearing IntrinsicHeight: both panels share one height whether
    // Preset Vol / BPM stack (a wrapping editor) or not.
    for (final (name, moduleId, fxId, isStacked) in const [
      ('AMP Brit 50JP', 3, 307, true),
      ('NR Gate', 0, 1, false),
    ]) {
      testWidgets('852x393: $name panels share one height', (tester) async {
        await pumpEditorPage(
          tester,
          size: const Size(852, 393),
          moduleId: moduleId,
          fxId: fxId,
        );

        final panel = find.byType(PresetFieldsPanel);

        expect(tester.widget<PresetFieldsPanel>(panel).stacked, isStacked);
        expect(
          tester.getSize(panel).height,
          tester.getSize(editorSurface()).height,
        );
        expect(tester.getSize(panel).width, 194);
      });
    }

    for (final size in const [Size(568, 320), Size(852, 300)]) {
      testWidgets('${label(size)} disconnected: the empty state fits', (
        tester,
      ) async {
        await pumpPage(tester, size: size, isConnected: false);

        expectNoOverflow(tester);
        expect(find.text('No device connected'), findsOneWidget);
      });
    }
  });

  group('phone failure modes', () {
    // Android Chrome's text-size setting reaches Flutter web as a text scale.
    // Compact knob captions then outgrow their 72-px dials: every cell, the
    // Preset panel included, must reflow instead of overflowing.
    for (final (name, moduleId, fxId, params, isCloneMode) in [
      ('NR Gate (Preset Vol / BPM side by side)', 0, 1, <int, num>{}, false),
      ...heavyEditors,
    ]) {
      testWidgets('640x360 at 130% text: $name does not overflow', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpEditorPage(
          tester,
          size: const Size(640, 360),
          moduleId: moduleId,
          fxId: fxId,
          params: params,
          isCloneMode: isCloneMode,
        );

        expectNoOverflow(tester);
        expect(tester.getSize(find.byType(PresetFieldsPanel)).width, 194);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    // Turning the phone to portrait (the app lays out at the 640 minimum) and
    // back re-decides whether Preset Vol / BPM stack: the IR editor wraps at
    // 640 but not at 852. A latched flag would leave the panels mismatched.
    testWidgets('a rotation re-decides the Preset Vol / BPM stacking', (
      tester,
    ) async {
      await pumpEditorPage(
        tester,
        size: const Size(852, 393),
        moduleId: 4,
        fxId: 416,
      );

      final panel = find.byType(PresetFieldsPanel);

      expect(tester.widget<PresetFieldsPanel>(panel).stacked, isFalse);

      tester.view.physicalSize = const Size(393, 852);
      await tester.pump();
      await tester.pump();

      expect(tester.widget<PresetFieldsPanel>(panel).stacked, isTrue);
      expect(
        tester.getSize(panel).height,
        tester.getSize(editorSurface()).height,
      );

      tester.view.physicalSize = const Size(852, 393);
      await tester.pump();
      await tester.pump();

      expect(tester.widget<PresetFieldsPanel>(panel).stacked, isFalse);
      expect(
        tester.getSize(panel).height,
        tester.getSize(editorSurface()).height,
      );
      expectNoOverflow(tester);
    });

    // Typing a knob value in a browser tab: the keyboard leaves the work area
    // ~12 px tall. Its min height (viewport - 2 x workPadding) must stay
    // clamped at 0, or BoxConstraints asserts on a negative minimum.
    testWidgets('740x280: a 220-px keyboard over an open knob editor', (
      tester,
    ) async {
      await pumpPage(tester, size: const Size(740, 280));

      final readout = tester.getCenter(inEditor(find.text('50')));

      await tester.tapAt(readout);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(readout);
      await tester.pump();

      expect(inEditor(find.byType(EditableText)), findsOneWidget);

      await setKeyboard(tester, 220);

      expect(tester.takeException(), isNull);
      expect(inEditor(find.byType(EditableText)), findsOneWidget);

      // Flushes the double-tap recognizer's timer.
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
