import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/theme/app_text.dart';
import 'package:sonicmaster/ui/module_editor.dart';
import 'package:sonicmaster/ui/preset_browser_page.dart';
import 'package:sonicmaster/ui/preset_fields_panel.dart';
import 'package:sonicmaster/ui/preset_rail.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/top_bar.dart';

import '../support/page_harness.dart';
import '../support/view_helpers.dart';

/// On the web the engine fetches a fallback face for a glyph the bundled fonts
/// lack only after the first layout, then reports `fontsChange`. The unsaved
/// marker "✱" (U+2731) is one: Oswald has no such glyph. RenderParagraph and
/// RenderEditable then lay their text out again, but keep answering intrinsics
/// and dry layout from a second painter that the font change never refreshes
/// (Flutter's `_textIntrinsicsCache`). The IntrinsicHeight that keeps the two
/// work-panels equal sized them from the line before the fallback, and the
/// taller panel overflowed.
///
/// Under flutter_test, a fallback family that the page's text lists but that
/// is registered only after the first frame replays that sequence: until it
/// loads, the test font stands in for it, and that font lacks U+2731 too, so
/// the marker shows Oswald's .notdef. The fixture is U+2731 from Noto Sans
/// Symbols 2, the face the web fetched. Its 0.63-em descent (Oswald's is
/// 0.289) is what makes a line taller.
void main() {
  const regular = Size(1614, 900);
  const compact = Size(898, 600);

  // Registers the fixture under [family]. Like the web's fallback fetch, the
  // load sends `fontsChange` to the framework.
  Future<void> loadSymbolFont(WidgetTester tester, String family) async {
    final bytes = File(
      'test/fixtures/fonts/noto_sans_symbols2_u2731.ttf',
    ).readAsBytesSync();

    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));

    await tester.runAsync(loader.load);
  }

  // The page, its text falling back to [family].
  Widget pageFallingBackTo(String family) => DefaultTextStyle.merge(
    style: TextStyle(fontFamilyFallback: [family]),
    child: const PresetBrowserPage(),
  );

  // The height [text] would have in [style] without a strut, falling back to
  // [family]: the line a fallback glyph makes when nothing pins it.
  double unpinnedLineHeight(String text, TextStyle style, String family) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontFamilyFallback: [family]),
      ),
      textDirection: .ltr,
    )..layout();

    final height = painter.height;

    painter.dispose();

    return height;
  }

  RenderParagraph editorTitle(WidgetTester tester, String text) =>
      tester.renderObject(
        find.descendant(
          of: find.byType(ModuleEditor),
          matching: find.text(text),
        ),
      );

  group('the editor title', () {
    // The page reproduces both layouts the overflow was seen in: regular,
    // and the compact one where the editor's Column was 680 px wide.
    for (final (name, size) in const [
      ('regular', regular),
      ('compact', compact),
    ]) {
      testWidgets(
        'the $name editor still fits its panel when the marker font loads late',
        (tester) async {
          final family = 'LateMarker-$name';

          await pumpPage(
            tester,
            size: size,
            home: pageFallingBackTo(family),
            overrides: [presetModifiedProvider.overrideWith((_) => true)],
          );
          expectNoOverflow(tester);

          final title = editorTitle(tester, 'NR  ✱');
          final width = title.size.width;

          await loadSymbolFont(tester, family);
          // fontsChange schedules RenderParagraph.systemFontsDidChange as a
          // frame callback: this frame runs it and lays the panels out again.
          await tester.pump();
          expectNoOverflow(tester);

          // The late face did reach the title: Noto's "✱" is wider than the
          // .notdef that stood in for it. Without this, a fixture that lost
          // its glyph or a load that never reports fontsChange would leave
          // every other check here passing.
          expect(title.size.width, greaterThan(width));
          expect(
            title.getMaxIntrinsicHeight(title.size.width),
            title.size.height,
            reason: 'the intrinsic pass must see the line the layout uses',
          );
        },
      );
    }

    testWidgets('the marker leaves the title on the Oswald line', (
      tester,
    ) async {
      // Loaded before the first frame, the fallback resolves at once, as on
      // desktop, where the title line grew from 24 to 29 px with the marker.
      const family = 'EarlyMarker';

      await loadSymbolFont(tester, family);

      final container = await pumpPage(
        tester,
        size: regular,
        home: pageFallingBackTo(family),
      );

      // round(16 px × Oswald's 1.482-em line).
      expect(editorTitle(tester, 'NR').size.height, 24);

      container.read(presetModifiedProvider.notifier).state = true;
      await tester.pump();
      expectNoOverflow(tester);

      expect(editorTitle(tester, 'NR  ✱').size.height, 24);
      // Unpinned, Oswald's 1.193-em ascent over the fallback's 0.63-em
      // descent makes the line round(16 × 1.823) = 29.
      expect(unpinnedLineHeight('NR  ✱', AppText.moduleTitle, family), 29);
    });
  });

  // Double-taps a knob's value [readout] to open its inline editor.
  Future<void> openEditor(WidgetTester tester, Finder readout) async {
    final spot = tester.getCenter(readout);

    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(spot);
    await tester.pump();
  }

  group('the knob value editor', () {
    // The field takes any text, so a typed glyph outside Oswald (an arrow, a
    // Persian digit, "✱") makes the web fetch a face just like the marker.
    // A module knob in regular, where the editor is the taller panel, and
    // Patch Vol in compact, where the Preset panel is. Lines: round(18 or
    // 14 px × 1.482 em) pinned, round(18 or 14 px × 1.823 em) unpinned.
    for (final (name, size, panel, readout, style, pinned, unpinned) in [
      (
        'a module knob, regular,',
        regular,
        ModuleEditor,
        '50',
        AppText.knobValue,
        27,
        33,
      ),
      (
        'Patch Vol, compact,',
        compact,
        PresetFieldsPanel,
        '44',
        AppText.knobValueCompact,
        21,
        26,
      ),
    ]) {
      testWidgets('$name still fits its panel when a typed glyph loads late', (
        tester,
      ) async {
        final family = 'LateTyped-$readout';

        Finder inPanel(Finder finder) =>
            find.descendant(of: find.byType(panel), matching: finder);

        await pumpPage(tester, size: size, home: pageFallingBackTo(family));
        await openEditor(tester, inPanel(find.text(readout)));
        await tester.enterText(inPanel(find.byType(EditableText)), '$readout✱');
        await tester.pump();
        expectNoOverflow(tester);

        await loadSymbolFont(tester, family);
        // RenderEditable.systemFontsDidChange runs in this frame's
        // callbacks, then the panels are laid out again.
        await tester.pump();
        expectNoOverflow(tester);

        final field = tester
            .state<EditableTextState>(inPanel(find.byType(EditableText)))
            .renderEditable;

        expect(field.size.height, pinned);
        expect(
          field.getMaxIntrinsicHeight(field.size.width),
          field.size.height,
          reason: 'the intrinsic pass must see the line the layout uses',
        );
        expect(unpinnedLineHeight('$readout✱', style, family), unpinned);

        // Flush the double-tap recognizer's timer before tearDown.
        await tester.pump(const Duration(milliseconds: 50));
      });
    }
  });

  testWidgets('the marker leaves the title-bar well its height', (
    tester,
  ) async {
    // Loaded before the first frame, as on desktop. The bar's height is
    // fixed, so the marker can't overflow it, but a taller marker line grew
    // the well around the preset name, on every first edit.
    const family = 'EarlyBarMarker';

    await loadSymbolFont(tester, family);

    final container = await pumpPage(
      tester,
      size: regular,
      home: pageFallingBackTo(family),
    );

    final well = find.ancestor(
      of: find.descendant(
        of: find.byType(TopBar),
        matching: find.byType(PresetSlotChip),
      ),
      matching: find.byType(SonicRecess),
    );

    final height = tester.getSize(well).height;

    container.read(presetModifiedProvider.notifier).state = true;
    await tester.pump();
    expectNoOverflow(tester);

    expect(tester.getSize(well).height, height);
    // Unpinned, the marker alone is a line of the fallback face only:
    // round(16 px × (1.069 + 0.63) em) = 27, against the name's 24.
    expect(unpinnedLineHeight('✱', AppText.presetTitle, family), 27);
  });
}
