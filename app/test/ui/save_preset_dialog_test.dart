import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/save_preset_dialog.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

import '../support/sonic_host.dart';
import '../support/view_helpers.dart';

/// Pumped in a bare [WidgetsApp] — the app is Material-free, so the dialog must
/// open without a Material ancestor or MaterialLocalizations.
void main() {
  // Opens SavePresetDialog exactly as the preset browser does, over a device
  // sitting on [current] with [names] already decoded.
  Future<void> open(
    WidgetTester tester, {
    PresetRef? current,
    Map<PresetRef, String> names = const {},
  }) async {
    late BuildContext ctx;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentPresetProvider.overrideWith((_) => current),
          presetNamesProvider.overrideWith((_) => names),
        ],
        child: WidgetsApp(
          color: const Color(0xFF000000),
          debugShowCheckedModeBanner: false,
          pageRouteBuilder:
              <T>(RouteSettings settings, WidgetBuilder builder) =>
                  PageRouteBuilder<T>(
                    settings: settings,
                    pageBuilder: (context, _, _) => builder(context),
                  ),
          home: Builder(
            builder: (context) {
              ctx = context;

              return const SizedBox();
            },
          ),
        ),
      ),
    );

    showSavePresetDialog(ctx); // the same entry point the preset browser uses
    await tester.pumpAndSettle();

    expect(find.text('Save preset'), findsOneWidget);
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).controller.text;

  testWidgets('prefills the current preset\'s decoded name', (tester) async {
    const current = PresetRef(.user, 5);

    await open(tester, current: current, names: {current: 'MyPatch'});

    expect(fieldText(tester), 'MyPatch');
    expect(find.text('7/10'), findsOneWidget); // the counter tracks the prefill
    expect(find.text('P05'), findsOneWidget); // slot defaults to the loaded one
  });

  testWidgets('prefills a Factory preset\'s name, not its label', (
    tester,
  ) async {
    const current = PresetRef(.factory, 3);

    await open(tester, current: current, names: {current: 'Crunch'});

    expect(fieldText(tester), 'Crunch');
    expect(find.text('P01'), findsOneWidget); // no User slot loaded -> P01
  });

  testWidgets('stays empty when the name dump has not been decoded', (
    tester,
  ) async {
    await open(tester, current: const PresetRef(.user, 5));

    expect(fieldText(tester), '');
  });

  testWidgets('outside-tap dismisses the dialog', (tester) async {
    const current = PresetRef(.user, 5);

    await open(tester, current: current, names: {current: 'MyPatch'});

    await tester.tapAt(const Offset(5, 5)); // barrier
    await tester.pumpAndSettle();

    expect(find.text('Save preset'), findsNothing);
  });

  group('Done / Enter in the real app shell', () {
    // Opens the dialog in SonicMasterApp at [size] (compact below 960x600)
    // with a soft keyboard [keyboard] px tall. The device tables never load,
    // so a save gives up at once and pops: a closed dialog means "saved".
    Future<void> openInShell(
      WidgetTester tester, {
      required Size size,
      double keyboard = 0,
    }) async {
      const current = PresetRef(.user, 5);

      final context = await pumpSonicHost(
        tester,
        size: size,
        keyboard: keyboard,
        overrides: [
          currentPresetProvider.overrideWith((_) => current),
          presetNamesProvider.overrideWith((_) => {current: 'MyPatch'}),
          dataAssetsProvider.overrideWith(
            (_) => Completer<DataAssets>().future,
          ),
        ],
      );

      unawaited(showSavePresetDialog(context));
      await tester.pumpAndSettle();
    }

    testWidgets('compact, keyboard up: Done closes it and saves nothing', (
      tester,
    ) async {
      await openInShell(tester, size: const Size(852, 393), keyboard: 180);
      await tester.testTextInput.receiveAction(.done);
      await tester.pump();

      expect(find.text('Save preset'), findsOneWidget); // still open
      expect(tester.testTextInput.isVisible, isFalse); // keyboard dismissed

      // The browser drops the inset once the keyboard is gone: the Slot
      // picker is in view and Save is still one tap away.
      await setKeyboard(tester, 0);
      await tester.pumpAndSettle();

      expectWithin(
        tester.getRect(find.text('P05')),
        const Rect.fromLTWH(0, 0, 852, 393),
        'the Slot picker',
      );
      expect(
        tester
            .widget<SonicButton>(find.widgetWithText(SonicButton, 'Save'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('compact, no soft keyboard: Enter still saves', (tester) async {
      // A phone or tablet with a hardware keyboard: nothing to dismiss.
      await openInShell(tester, size: const Size(852, 393));
      await tester.testTextInput.receiveAction(.done);
      await tester.pumpAndSettle();

      expect(find.text('Save preset'), findsNothing);
    });

    testWidgets('regular: Done saves, keyboard or not (unchanged)', (
      tester,
    ) async {
      await openInShell(tester, size: const Size(1280, 800), keyboard: 300);
      await tester.testTextInput.receiveAction(.done);
      await tester.pumpAndSettle();

      expect(find.text('Save preset'), findsNothing);
    });
  });
}
