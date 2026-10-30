import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/edit_providers.dart';
import 'package:sonicmaster/ui/chain_view.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/module_editor.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

import '../support/page_harness.dart';
import '../support/view_helpers.dart';

/// A live flip between the two layouts (a phone turned sideways, a browser
/// window dragged across the 960 / 600 lines) re-lays the page out under the
/// same widget tree. Sizes and parameters vary by mode, never widget types, so
/// the elements of the work area must survive the flip: a rebuilt element
/// drops its state (an open dropdown, a knob's number field and its focus, the
/// tap-tempo timer) in the middle of a gesture.
///
/// Fake time: zero-length pumps only, far below the connected heartbeat's 2 s.
void main() {
  const regular = Size(1280, 800);
  const compact = Size(852, 393);

  // AMP Brit 50JP: knobs, a Clone Mode toggle and a foot-switch cell, and the
  // effect dropdown and on/off toggle in the header.
  Future<void> pumpAmpPage(WidgetTester tester, Size size) => pumpPage(
    tester,
    size: size,
    selectedEffects: const {3: 307},
    parameters: const {3: {}},
    overrides: [selectedModuleProvider.overrideWith((_) => 3)],
  );

  /// Resizes the view under the mounted page; the second pump runs the
  /// post-frame knob-row measurement the flip schedules.
  Future<void> flipTo(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await tester.pump();
    await tester.pump();
  }

  // The elements a finder matches, in tree order.
  List<Element> elementsOf(Finder finder) => finder.evaluate().toList();

  /// The kinds in [before] whose elements are not, instance for instance and in
  /// order, the ones in [after]: empty when the flip rebuilt nothing. An
  /// Element has no value equality, so listEquals compares instances.
  List<String> rebuiltKinds(
    Map<String, List<Element>> before,
    Map<String, List<Element>> after,
  ) => [
    for (final MapEntry(:key, :value) in before.entries)
      if (!listEquals(value, after[key])) key,
  ];

  Finder inEditor(Finder finder) =>
      find.descendant(of: find.byType(ModuleEditor), matching: finder);

  // The editor and the pieces of it that a mode switch might re-create. The
  // header's controls are listed apart from the cells on purpose: the page
  // gives the knob row a GlobalKey, so a new wrapper above the row would carry
  // its cells over as the same elements and rebuild only the header. The
  // effect description (regular only) is left out: it comes and goes.
  Map<String, List<Element>> editorElements() => {
    'ModuleEditor': elementsOf(find.byType(ModuleEditor)),
    'effect dropdown': elementsOf(inEditor(find.byType(SonicDropdown<int>))),
    'toggles': elementsOf(inEditor(find.byType(SonicToggle))),
    'panel cells': elementsOf(inEditor(find.byType(PanelCell))),
    'knob cells': elementsOf(inEditor(find.byType(KnobControl))),
  };

  Size dial(WidgetTester tester) =>
      tester.getSize(inEditor(find.byKey(const Key('knob'))).first);

  testWidgets('the module editor keeps its elements across a live flip', (
    tester,
  ) async {
    await pumpAmpPage(tester, regular);

    final before = editorElements();

    // Every kind must match something, or its check passes without checking
    // ([] equals []).
    expect(before.values, everyElement(isNotEmpty));
    expect(dial(tester), const Size.square(120));

    await flipTo(tester, compact);

    expectNoOverflow(tester);
    expect(rebuiltKinds(before, editorElements()), isEmpty);
    expect(dial(tester), const Size.square(72));

    await flipTo(tester, regular);

    expectNoOverflow(tester);
    expect(rebuiltKinds(before, editorElements()), isEmpty);
    expect(dial(tester), const Size.square(120));
  });

  Map<String, List<Element>> chainElements() => {
    'ChainView': elementsOf(find.byType(ChainView)),
    'ModuleCard': elementsOf(find.byType(ModuleCard)),
  };

  Iterable<double> cardWidths() =>
      elementsOf(find.byType(ModuleCard)).map((element) => element.size!.width);

  // How far apart the cards' top edges are: ~0 on one row (the amp block's
  // cards sit inside its 4-px padding), ~110 once a second row starts.
  double cardTopSpread(WidgetTester tester) {
    final tops = elementsOf(find.byType(ModuleCard))
        .map((element) => tester.getTopLeft(find.byWidget(element.widget)).dy)
        .toList();

    return tops.reduce((a, b) => a > b ? a : b) -
        tops.reduce((a, b) => a < b ? a : b);
  }

  testWidgets('the signal chain keeps its cards across a live flip', (
    tester,
  ) async {
    await pumpAmpPage(tester, regular);

    final before = chainElements();

    expect(before['ChainView'], hasLength(1));
    expect(before['ModuleCard'], hasLength(9));
    expect(cardWidths(), everyElement(96));

    await flipTo(tester, compact);

    expectNoOverflow(tester);
    expect(rebuiltKinds(before, chainElements()), isEmpty);
    expect(cardWidths(), everyElement(77));
    expect(cardTopSpread(tester), lessThanOrEqualTo(4));

    await flipTo(tester, regular);

    expectNoOverflow(tester);
    expect(rebuiltKinds(before, chainElements()), isEmpty);
    expect(cardWidths(), everyElement(96));
  });
}
