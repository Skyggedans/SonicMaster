import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/chain_view.dart';
import 'package:sonicmaster/ui/preset_browser_page.dart';

import 'page_harness.dart';
import 'silent_transport.dart';

void main() {
  testWidgets('connected: the loaded preset, its chain and the device name', (
    tester,
  ) async {
    await pumpPage(tester, size: const Size(1280, 800));

    expect(tester.takeException(), isNull);
    expect(find.byType(PresetBrowserPage), findsOneWidget);
    expect(find.text('Clean'), findsWidgets);
    expect(find.text('Smart Box'), findsOneWidget);
    expect(find.byType(ModuleCard), findsNWidgets(9));
    expect(find.text('No device connected'), findsNothing);
  });

  testWidgets('disconnected: the empty work area and a Connect button', (
    tester,
  ) async {
    await pumpPage(tester, size: const Size(1280, 800), isConnected: false);

    expect(tester.takeException(), isNull);
    expect(find.text('No device connected'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  // pumpPage fakes a live pedal by default (connectionStateProvider = true):
  // the overrides it is given come last and must win.
  testWidgets('caller overrides win over the harness fixture', (tester) async {
    final container = await pumpPage(
      tester,
      size: const Size(1280, 800),
      overrides: [connectionStateProvider.overrideWith((ref) => false)],
    );

    expect(container.read(connectionStateProvider), isFalse);
    expect(find.text('No device connected'), findsOneWidget);
  });

  testWidgets('a preset load stays in flight until the ACK timeout', (
    tester,
  ) async {
    final container = await pumpPage(tester, size: const Size(1280, 800));

    await tester.tap(find.text('P02'));
    await tester.pump();

    expect(container.read(presetLoadingProvider), isTrue);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(() async {});
    await tester.pump();

    expect(container.read(presetLoadingProvider), isTrue);

    await pumpPastAckTimeout(tester);

    expect(container.read(presetLoadingProvider), isFalse);
    expect(container.read(presetLoadStatusProvider), 'P02: no ACK (timeout)');
  });

  // A phone's BLE link can drop a reply: a pick the pedal never answers must
  // end after its timeout, leaving the list usable for the next pick.
  testWidgets('a pick the pedal never answers ends; the next one goes out', (
    tester,
  ) async {
    final container = await pumpPage(tester, size: const Size(1280, 800));

    await tester.tap(find.text('P02'));
    await tester.pump();
    await pumpPastAckTimeout(tester);

    expect(container.read(presetLoadingProvider), isFalse);

    await tester.tap(find.text('P03'));
    await tester.pump();

    expect(container.read(presetLoadingProvider), isTrue);

    await pumpPastAckTimeout(tester);

    expect(container.read(presetLoadStatusProvider), 'P03: no ACK (timeout)');
  });
}
