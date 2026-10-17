import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/layout_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/knob_control.dart';
import 'package:sonicmaster/ui/preset_rail.dart';

import '../support/fonts.dart';
import '../support/silent_transport.dart';
import '../support/test_assets.dart';

/// The rail tests that don't pick anything.
void _ignorePick(PresetRef _) {}

/// The rail tests that don't turn Master Vol.
void _ignoreVolume(int _) {}

void main() {
  // The tabs, search, and chip list only show once connected, so these tests
  // render the rail in the connected state.
  Widget connectedRail([
    List<Override> extra = const [],
  ]) => UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [connectionStateProvider.overrideWith((_) => true), ...extra],
    ),
    child: const MaterialApp(
      home: Scaffold(
        body: PresetRail(onPick: _ignorePick, onMasterVolume: _ignoreVolume),
      ),
    ),
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
          child: MaterialApp(
            home: Scaffold(
              body: PresetRail(
                onPick: _ignorePick,
                onMasterVolume: _ignoreVolume,
              ),
            ),
          ),
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
        child: MaterialApp(
          home: Scaffold(
            body: PresetRail(
              onPick: _ignorePick,
              onMasterVolume: _ignoreVolume,
            ),
          ),
        ),
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
        child: const MaterialApp(
          home: Scaffold(
            body: PresetRail(
              onPick: _ignorePick,
              onMasterVolume: _ignoreVolume,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(KnobControl), findsOneWidget);
    expect(find.text('MASTER VOL'), findsOneWidget); // knob label is uppercased
  });

  // The rail's search field is remounted whenever its subtree is: a mode flip
  // (rail <-> compact drawer) or a pedal drop and reconnect. The filter lives
  // in presetSearchProvider and outlives the field, so the field must show it.
  testWidgets('the search box shows the active filter after a remount', (
    tester,
  ) async {
    await loadOswald();
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [connectionStateProvider.overrideWith((_) => true)],
    );

    final rail = UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: PresetRail(onPick: _ignorePick, onMasterVolume: _ignoreVolume),
        ),
      ),
    );

    addTearDown(container.dispose);
    await tester.pumpWidget(rail);
    await tester.enterText(find.byType(EditableText), 'P06');
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(rail);

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'P06',
    );
    expect(
      find.descendant(of: find.byType(ListView), matching: find.text('P06')),
      findsOneWidget,
    );
    expect(find.text('P01'), findsNothing);
  });

  testWidgets('a filter survives a reconnect and can still be cleared', (
    tester,
  ) async {
    await loadOswald();
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [connectionStateProvider.overrideWith((_) => true)],
    );

    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: PresetRail(
              onPick: _ignorePick,
              onMasterVolume: _ignoreVolume,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(EditableText), 'P06');
    await tester.pump();

    // The pedal drops (the browser block unmounts) and comes back.
    container.read(connectionStateProvider.notifier).state = false;
    await tester.pump();
    container.read(connectionStateProvider.notifier).state = true;
    await tester.pump();

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'P06',
    );

    await tester.enterText(find.byType(EditableText), '');
    await tester.pump();

    expect(container.read(presetSearchProvider), isEmpty);
    expect(find.text('P01'), findsOneWidget);
  });

  testWidgets('tapping a row hands its preset to onPick', (tester) async {
    await loadOswald();
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final picked = <PresetRef>[];
    final container = ProviderContainer(
      overrides: [connectionStateProvider.overrideWith((_) => true)],
    );

    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: PresetRail(onPick: picked.add, onMasterVolume: _ignoreVolume),
          ),
        ),
      ),
    );
    await tester.tap(find.text('P03'));

    expect(picked, [const PresetRef(.user, 3)]);
  });

  // The compact drawer stacks these pieces in one scroll list of its own.
  testWidgets(
    'the rail pieces stand alone; currentRowKey tags the loaded row',
    (tester) async {
      await loadOswald();
      tester.view.physicalSize = const Size(600, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final currentRowKey = GlobalKey();
      final container = ProviderContainer(
        overrides: [
          connectionStateProvider.overrideWith((_) => true),
          currentPresetProvider.overrideWith((_) => const PresetRef(.user, 7)),
        ],
      );

      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    const RailControls(onMasterVolume: _ignoreVolume),
                    PresetChipColumn(
                      onPick: _ignorePick,
                      currentRowKey: currentRowKey,
                    ),
                    const RailFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('MASTER VOL'), findsOneWidget);
      expect(find.text('FACTORY'), findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget);
      expect(find.byType(PresetChip), findsNWidgets(50));
      expect(find.text('by Skyggedans'), findsOneWidget);
      expect((currentRowKey.currentWidget! as PresetChip).slot, 'P07');
    },
  );

  group('pickPreset', () {
    final assets = loadTestDataAssets();

    // A bare host whose context and ref stand in for the page's.
    Future<(BuildContext, WidgetRef, ProviderContainer)> pumpHost(
      WidgetTester tester, {
      bool isModified = false,
    }) async {
      final container = ProviderContainer(
        overrides: [
          deviceServiceProvider.overrideWith((ref) {
            final service = DeviceService(SilentTransport())..startListening();

            ref.onDispose(service.dispose);

            return service;
          }),
          dataAssetsProvider.overrideWith((_) => assets),
          presetDrawerOpenProvider.overrideWith((_) => true),
          presetModifiedProvider.overrideWith((_) => isModified),
        ],
      );

      addTearDown(container.dispose);
      await container.read(dataAssetsProvider.future);

      late BuildContext hostContext;
      late WidgetRef hostRef;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                hostContext = context;
                hostRef = ref;

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      return (hostContext, hostRef, container);
    }

    testWidgets('a clean pick closes the drawer and loads the preset', (
      tester,
    ) async {
      final (context, ref, container) = await pumpHost(tester);

      unawaited(pickPreset(context, ref, const PresetRef(.user, 2)));
      await tester.pump();

      expect(container.read(presetDrawerOpenProvider), isFalse);
      expect(container.read(presetLoadingProvider), isTrue);

      await pumpPastAckTimeout(tester);

      expect(container.read(presetLoadStatusProvider), 'P02: no ACK (timeout)');
    });

    testWidgets('unsaved edits + Cancel keep the drawer open, load nothing', (
      tester,
    ) async {
      final (context, ref, container) = await pumpHost(
        tester,
        isModified: true,
      );

      unawaited(pickPreset(context, ref, const PresetRef(.user, 2)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(presetDrawerOpenProvider), isTrue);
      expect(container.read(presetLoadingProvider), isFalse);
      expect(container.read(presetLoadStatusProvider), isNull);
    });

    testWidgets('unsaved edits + Discard close the drawer and load', (
      tester,
    ) async {
      final (context, ref, container) = await pumpHost(
        tester,
        isModified: true,
      );

      unawaited(pickPreset(context, ref, const PresetRef(.user, 2)));
      await tester.pumpAndSettle();

      expect(container.read(presetDrawerOpenProvider), isTrue);

      await tester.tap(find.text('Discard'));
      await tester.pump();

      expect(container.read(presetDrawerOpenProvider), isFalse);
      expect(container.read(presetLoadingProvider), isTrue);

      await tester.pumpAndSettle();
      await pumpPastAckTimeout(tester);

      expect(container.read(presetLoadStatusProvider), 'P02: no ACK (timeout)');
    });
  });
}
