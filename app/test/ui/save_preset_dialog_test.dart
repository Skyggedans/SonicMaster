import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/save_preset_dialog.dart';

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
}
