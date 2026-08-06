import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/state/connection_prefs.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/state/reconnect.dart';
import 'package:sonicmaster/ui/connection_controls.dart';

/// A no-I/O transport whose connect() always succeeds (mirrors the one in
/// reconnect_test.dart; kept local so this file stands alone).
class _FakeTransport implements Transport {
  @override
  Future<void> connect({String? target}) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Stream<Uint8List> rawPackets() => const Stream<Uint8List>.empty();
  @override
  Future<void> sendFrame(String frameHex) async {}
  @override
  Stream<bool>? connectionEvents() => null;
}

/// A [ConnectionPrefs] whose writes always fail — proves a persistence failure
/// after a successful connect is not reported as a connect failure.
class _ThrowingPrefs extends ConnectionPrefs {
  _ThrowingPrefs(super.prefs);
  @override
  Future<void> saveProfile(TransportKind t, String? n) async =>
      throw StateError('prefs down');
  @override
  Future<void> clearAutoConnect() async => throw StateError('prefs down');
}

Future<void> _loadFont() async {
  final fl = FontLoader('Oswald')
    ..addFont(rootBundle.load('assets/fonts/Oswald.ttf'));

  await fl.load();
}

void main() {
  testWidgets('disconnected: Disconnected status + a compact Connect button', (
    tester,
  ) async {
    await _loadFont();
    tester.view.physicalSize = const Size(800, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ConnectionControls())),
      ),
    );
    await tester.pump();

    expect(find.text('Disconnected'), findsOneWidget);
    // Connect/Disconnect now lives in the device well, right of the dot.
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Disconnect'), findsNothing);
  });

  testWidgets('connected: Connected status + a Disconnect button', (
    tester,
  ) async {
    await _loadFont();
    tester.view.physicalSize = const Size(800, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [connectionStateProvider.overrideWith((_) => true)],
    );

    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ConnectionControls())),
      ),
    );
    await tester.pump();

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
  });

  testWidgets('when connected, shows the device name instead of "Connected"', (
    tester,
  ) async {
    await _loadFont();
    tester.view.physicalSize = const Size(800, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        connectionStateProvider.overrideWith((_) => true),
        connectedDeviceNameProvider.overrideWith((_) => 'My Pedal BLE'),
      ],
    );

    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ConnectionControls())),
      ),
    );
    await tester.pump();

    expect(find.text('My Pedal BLE'), findsOneWidget);
    expect(find.text('Connected'), findsNothing);
  });

  testWidgets(
    'a prefs failure after a successful connect still reports connected',
    (tester) async {
      // The picker now returns the target; this exercises the post-pick helper
      // (connectAndPersist) directly, since the picker can't enumerate real
      // devices in a widget test.
      SharedPreferences.setMockInitialValues({});
      final prefs = _ThrowingPrefs(await SharedPreferences.getInstance());
      final container = ProviderContainer(
        overrides: [
          transportKindProvider.overrideWith((_) => .usb),
          deviceServiceProvider.overrideWith(
            (_) => DeviceService(_FakeTransport()),
          ),
          connectionPrefsProvider.overrideWithValue(prefs),
          // Short-circuit the post-connect global read so the connect needs no timers.
          presetLoadingProvider.overrideWith((_) => true),
        ],
      );

      addTearDown(container.dispose);

      late WidgetRef ref;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (_, r, _) {
              ref = r;

              return const SizedBox();
            },
          ),
        ),
      );

      await connectAndPersist(ref, target: 'Smart Box');
      await tester.pumpAndSettle();

      // saveProfile threw, but the connection genuinely succeeded — status must
      // reflect the connection, not "connect failed".
      expect(container.read(presetLoadStatusProvider), 'connected');
      expect(container.read(connectionStateProvider), isTrue);
    },
  );
}
