import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/preset_rail.dart';

void main() {
  // The tabs, search, and chip list only show once connected, so these tests
  // render the rail in the connected state.
  Widget connectedRail([List<Override> extra = const []]) =>
      UncontrolledProviderScope(
        container: ProviderContainer(
          overrides: [
            connectionStateProvider.overrideWith((_) => true),
            ...extra,
          ],
        ),
        child: const MaterialApp(home: Scaffold(body: PresetRail())),
      );

  testWidgets('renders tabs, search, and User chips', (tester) async {
    final fl = FontLoader('Oswald')
      ..addFont(rootBundle.load('assets/fonts/Oswald.ttf'));

    await fl.load();
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(connectedRail());
    await tester.pump();

    expect(find.text('FACTORY'), findsOneWidget);
    expect(find.text('USER'), findsOneWidget);
    // User tab active by default -> User chips visible, Factory chips not.
    expect(find.text('P01'), findsOneWidget);
    expect(find.text('F01'), findsNothing);
  });

  testWidgets(
    'shows the browser only when connected; no connect button in rail',
    (tester) async {
      final fl = FontLoader('Oswald')
        ..addFont(rootBundle.load('assets/fonts/Oswald.ttf'));

      await fl.load();
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Disconnected: the rail is empty — no browser, and no Connect/Disconnect
      // (that moved to the top bar's device well).
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: PresetRail())),
        ),
      );
      await tester.pump();
      expect(find.text('Connect'), findsNothing);
      expect(find.text('Disconnect'), findsNothing);
      expect(find.text('FACTORY'), findsNothing);

      // Connected: the browser appears; still no Connect/Disconnect in the rail.
      await tester.pumpWidget(connectedRail());
      await tester.pump();
      expect(find.text('FACTORY'), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
      expect(find.text('Disconnect'), findsNothing);
    },
  );

  testWidgets('switching the tab shows the Factory bank', (tester) async {
    final fl = FontLoader('Oswald')
      ..addFont(rootBundle.load('assets/fonts/Oswald.ttf'));

    await fl.load();
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      connectedRail([presetTabProvider.overrideWith((_) => .factory)]),
    );
    await tester.pump();
    expect(find.text('F01'), findsOneWidget);
    expect(find.text('P01'), findsNothing);
  });

  testWidgets('typing in search filters the chip list', (tester) async {
    final fl = FontLoader('Oswald')
      ..addFont(rootBundle.load('assets/fonts/Oswald.ttf'));

    await fl.load();
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(connectedRail());
    await tester.pump();
    expect(find.text('P01'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'P06');
    await tester.pump();
    // Scoped to the chip list: after entering text, the search TextField's
    // own EditableText also contains "P06", so an unscoped find.text('P06')
    // would (correctly) match two widgets.
    expect(
      find.descendant(of: find.byType(ListView), matching: find.text('P06')),
      findsOneWidget,
    );
    expect(find.text('P01'), findsNothing);
  });

  testWidgets('the Master volume knob shows in the rail only when connected', (
    tester,
  ) async {
    final fl = FontLoader('Oswald')
      ..addFont(rootBundle.load('assets/fonts/Oswald.ttf'));

    await fl.load();
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Disconnected: no Master knob.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: PresetRail())),
      ),
    );
    await tester.pump();
    expect(find.byType(KnobControl), findsNothing);

    // Connected: the Master knob appears, labelled.
    final container = ProviderContainer(
      overrides: [connectionStateProvider.overrideWith((_) => true)],
    );

    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PresetRail())),
      ),
    );
    await tester.pump();
    expect(find.byType(KnobControl), findsOneWidget);
    expect(find.text('MASTER VOL'), findsOneWidget); // knob label is uppercased
  });
}
