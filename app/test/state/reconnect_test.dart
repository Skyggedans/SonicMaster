import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonicmaster/device/device_model.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/state/connection_prefs.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/state/reconnect.dart';

import '../support/test_assets.dart';

/// A no-I/O transport. [connectGate], if set, defers connect() completion so a
/// test can flip the transport mid-await; otherwise connect() resolves at once.
/// [failConnect] makes connect() throw.
class FakeTransport implements Transport {
  FakeTransport({this.connectGate, this.failConnect = false});
  final Completer<void>? connectGate;
  final bool failConnect;
  int connectCount = 0;
  int disconnectCount = 0;
  String? lastTarget;

  @override
  Future<void> connect({String? target}) async {
    connectCount++;
    lastTarget = target;

    if (connectGate != null) await connectGate!.future;

    if (failConnect) throw StateError('connect failed');
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
  }

  @override
  Stream<Uint8List> rawPackets() => const Stream<Uint8List>.empty();
  @override
  Future<void> sendFrame(String frameHex) async {}
  @override
  Stream<bool>? connectionEvents() => null;
}

/// Pumps a bare Consumer and hands back a live [WidgetRef] (mirrors the existing
/// preset_rail_foundation_test pattern).
Future<WidgetRef> pumpRef(
  WidgetTester tester,
  ProviderContainer container,
) async {
  late WidgetRef captured;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (_, ref, _) {
          captured = ref;
          return const SizedBox();
        },
      ),
    ),
  );

  return captured;
}

/// A [ConnectionPrefs] whose writes always fail — proves the callers treat
/// persistence as best-effort (a prefs failure must not abort the surrounding
/// connect/disconnect flow).
class _ThrowingPrefs extends ConnectionPrefs {
  _ThrowingPrefs(super.prefs);
  @override
  Future<void> saveProfile(TransportKind t, String? n) async =>
      throw StateError('prefs down');
  @override
  Future<void> clearAutoConnect() async => throw StateError('prefs down');
}

void main() {
  testWidgets('connectAndSync marks live + records the BLE target on success', (
    tester,
  ) async {
    final fake = FakeTransport();
    final container = ProviderContainer(
      overrides: [
        transportKindProvider.overrideWith((_) => .ble),
        deviceServiceProvider.overrideWith((_) => DeviceService(fake)),
        // Short-circuit the post-connect global read so the test needs no timers.
        presetLoadingProvider.overrideWith((_) => true),
      ],
    );

    addTearDown(container.dispose);
    final ref = await pumpRef(tester, container);

    final ok = await connectAndSync(
      ref,
      target: 'My Pedal',
      statusOnSuccess: 'connected',
    );

    expect(ok, isTrue);
    expect(fake.connectCount, 1);
    expect(container.read(connectionStateProvider), isTrue);
    expect(container.read(lastBleTargetProvider), 'My Pedal');
    expect(container.read(presetLoadStatusProvider), 'connected');
  });

  testWidgets(
    'connectAndSync bails (false, not live) if transport switches mid-connect',
    (tester) async {
      final gate = Completer<void>();
      final fake = FakeTransport(connectGate: gate);
      final container = ProviderContainer(
        overrides: [
          transportKindProvider.overrideWith((_) => .ble),
          deviceServiceProvider.overrideWith((_) => DeviceService(fake)),
          presetLoadingProvider.overrideWith((_) => true),
        ],
      );

      addTearDown(container.dispose);
      final ref = await pumpRef(tester, container);

      final future = connectAndSync(
        ref,
        target: 'My Pedal',
        statusOnSuccess: 'connected',
      );

      // User flips transport while connect() is in flight.
      container.read(transportKindProvider.notifier).state = .usb;
      gate.complete();
      final ok = await future;

      expect(ok, isFalse);
      expect(container.read(connectionStateProvider), isFalse);
      expect(container.read(lastBleTargetProvider), isNull);
      expect(container.read(presetLoadStatusProvider), isNot('connected'));
    },
  );

  testWidgets('connectAndSync rethrows on connect failure and stays not-live', (
    tester,
  ) async {
    final fake = FakeTransport(failConnect: true);
    final container = ProviderContainer(
      overrides: [
        transportKindProvider.overrideWith((_) => .usb),
        deviceServiceProvider.overrideWith((_) => DeviceService(fake)),
      ],
    );

    addTearDown(container.dispose);
    final ref = await pumpRef(tester, container);

    await expectLater(
      connectAndSync(ref, target: null, statusOnSuccess: 'connected'),
      throwsA(isA<StateError>()),
    );
    expect(container.read(connectionStateProvider), isFalse);
  });

  testWidgets('disconnectDevice disarms auto-connect', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = ConnectionPrefs(await SharedPreferences.getInstance());

    await prefs.saveProfile(.ble, 'My Pedal'); // armed
    final fake = FakeTransport();
    final container = ProviderContainer(
      overrides: [
        connectionPrefsProvider.overrideWithValue(prefs),
        deviceServiceProvider.overrideWith((_) => DeviceService(fake)),
      ],
    );

    addTearDown(container.dispose);
    final ref = await pumpRef(tester, container);

    await disconnectDevice(ref);

    expect(prefs.autoConnectProfile, isNull);
    expect(container.read(connectionStateProvider), isFalse);
  });

  testWidgets('a connection drop does not disarm auto-connect', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = ConnectionPrefs(await SharedPreferences.getInstance());

    await prefs.saveProfile(.usb, null); // armed, USB
    final container = ProviderContainer(
      overrides: [
        connectionPrefsProvider.overrideWithValue(prefs),
        // USB => handleConnectionDrop takes its early-return guard and never
        // touches prefs (the guarantee holds for the BLE path too — the function
        // makes no prefs call on any path).
        transportKindProvider.overrideWith((_) => .usb),
      ],
    );

    addTearDown(container.dispose);
    final ref = await pumpRef(tester, container);

    await handleConnectionDrop(ref);

    expect(prefs.autoConnectProfile, isNotNull); // still armed
  });

  testWidgets(
    'disconnectDevice closes the transport even if the prefs write fails',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = _ThrowingPrefs(await SharedPreferences.getInstance());
      final fake = FakeTransport();
      final container = ProviderContainer(
        overrides: [
          connectionPrefsProvider.overrideWithValue(prefs),
          deviceServiceProvider.overrideWith((_) => DeviceService(fake)),
        ],
      );

      addTearDown(container.dispose);
      final ref = await pumpRef(tester, container);

      // Must not throw even though clearAutoConnect() throws.
      await disconnectDevice(ref);

      expect(fake.disconnectCount, 1); // transport closed despite prefs failure
      expect(container.read(connectionStateProvider), isFalse);
    },
  );

  testWidgets('autoConnectOnStartup does nothing when not armed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = ConnectionPrefs(
      await SharedPreferences.getInstance(),
    ); // unarmed
    final fake = FakeTransport();
    final container = ProviderContainer(
      overrides: [
        connectionPrefsProvider.overrideWithValue(prefs),
        deviceServiceProvider.overrideWith((_) => DeviceService(fake)),
      ],
    );

    addTearDown(container.dispose);
    final ref = await pumpRef(tester, container);

    await autoConnectOnStartup(ref);

    expect(fake.connectCount, 0);
    expect(container.read(connectionStateProvider), isFalse);
  });

  testWidgets('autoConnectOnStartup restores USB and connects when armed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = ConnectionPrefs(await SharedPreferences.getInstance());

    await prefs.saveProfile(.usb, null);
    final fake = FakeTransport();
    final container = ProviderContainer(
      overrides: [
        connectionPrefsProvider.overrideWithValue(prefs),
        deviceServiceProvider.overrideWith((_) => DeviceService(fake)),
        presetLoadingProvider.overrideWith((_) => true),
      ],
    );

    addTearDown(container.dispose);
    final ref = await pumpRef(tester, container);

    await autoConnectOnStartup(ref);

    expect(container.read(transportKindProvider), TransportKind.usb);
    expect(fake.connectCount, 1);
    expect(container.read(connectionStateProvider), isTrue);
  });

  testWidgets('autoConnectOnStartup reports a status when USB connect fails', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = ConnectionPrefs(await SharedPreferences.getInstance());

    await prefs.saveProfile(.usb, null);
    final fake = FakeTransport(failConnect: true);
    final container = ProviderContainer(
      overrides: [
        connectionPrefsProvider.overrideWithValue(prefs),
        deviceServiceProvider.overrideWith((_) => DeviceService(fake)),
      ],
    );

    addTearDown(container.dispose);
    final ref = await pumpRef(tester, container);

    await autoConnectOnStartup(ref);

    expect(container.read(connectionStateProvider), isFalse);
    expect(
      container.read(presetLoadStatusProvider),
      'auto-connect failed — tap Connect',
    );
  });

  testWidgets(
    'autoConnectOnStartup restores BLE + target and connects when armed',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = ConnectionPrefs(await SharedPreferences.getInstance());

      await prefs.saveProfile(.ble, 'My Pedal');
      final fake = FakeTransport();
      final container = ProviderContainer(
        overrides: [
          connectionPrefsProvider.overrideWithValue(prefs),
          deviceServiceProvider.overrideWith((_) => DeviceService(fake)),
          presetLoadingProvider.overrideWith(
            (_) => true,
          ), // short-circuit refreshGlobalSettings
        ],
      );

      addTearDown(container.dispose);
      final ref = await pumpRef(tester, container);

      await autoConnectOnStartup(ref);

      expect(container.read(transportKindProvider), TransportKind.ble);
      expect(container.read(lastBleTargetProvider), 'My Pedal');
      expect(fake.connectCount, 1);
      expect(fake.lastTarget, 'My Pedal');
      expect(container.read(connectionStateProvider), isTrue);
    },
  );

  testWidgets(
    'autoConnectOnStartup on BLE failure routes into the reconnect backoff',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = ConnectionPrefs(await SharedPreferences.getInstance());

      await prefs.saveProfile(.ble, 'My Pedal');
      final fake = FakeTransport(failConnect: true);
      final container = ProviderContainer(
        overrides: [
          connectionPrefsProvider.overrideWithValue(prefs),
          deviceServiceProvider.overrideWith((_) => DeviceService(fake)),
        ],
      );

      addTearDown(container.dispose);
      final ref = await pumpRef(tester, container);

      final future = autoConnectOnStartup(
        ref,
      ); // don't await yet — drive timers

      await tester
          .pump(); // enters handleConnectionDrop, sets reconnecting=true
      expect(
        container.read(reconnectingProvider),
        isTrue,
      ); // routed to BLE backoff, not USB status
      // Drain the three backoff delays so the loop exhausts and no timer is pending.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 1200));
      await future;

      expect(container.read(connectionStateProvider), isFalse);
      expect(container.read(reconnectingProvider), isFalse);
      expect(
        container.read(presetLoadStatusProvider),
        contains('reconnect failed'),
      );
    },
  );

  testWidgets('connectAndSync detects the model from the connection name', (
    tester,
  ) async {
    final fake = FakeTransport();
    final container = ProviderContainer(
      overrides: [
        transportKindProvider.overrideWith((_) => .ble),
        deviceServiceProvider.overrideWith((_) => DeviceService(fake)),
        dataAssetsProvider.overrideWith((_) => loadTestDataAssets()),
        presetLoadingProvider.overrideWith((_) => true),
      ],
    );

    addTearDown(container.dispose);
    await container.read(dataAssetsProvider.future); // resolve before connect
    final ref = await pumpRef(tester, container);

    await connectAndSync(
      ref,
      target: 'Smart Box BLE',
      statusOnSuccess: 'connected',
    );

    expect(container.read(detectedDeviceModelProvider), DeviceModel.smartBox);
  });

  testWidgets('applyUserDisconnect resets the detected model to unknown', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [detectedDeviceModelProvider.overrideWith((_) => .smartBox)],
    );

    addTearDown(container.dispose);
    final ref = await pumpRef(tester, container);

    applyUserDisconnect(ref);

    expect(container.read(detectedDeviceModelProvider), DeviceModel.unknown);
  });

  testWidgets('a USB drop resets the detected model to unknown', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        transportKindProvider.overrideWith((_) => .usb),
        detectedDeviceModelProvider.overrideWith((_) => .pocketMaster),
      ],
    );

    addTearDown(container.dispose);
    final ref = await pumpRef(tester, container);

    await handleConnectionDrop(ref); // USB => early-returns after the reset

    expect(container.read(detectedDeviceModelProvider), DeviceModel.unknown);
  });

  testWidgets('handleUsbConnectionLost disconnects and clears model + name', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [detectedDeviceModelProvider.overrideWith((_) => .smartBox)],
    );

    addTearDown(container.dispose);
    final ref = await pumpRef(tester, container);

    container.read(connectionStateProvider.notifier).state = true;
    container.read(connectedDeviceNameProvider.notifier).state = 'Smart Box';

    handleUsbConnectionLost(ref);

    expect(container.read(connectionStateProvider), isFalse);
    expect(container.read(connectedDeviceNameProvider), isNull);
    expect(container.read(detectedDeviceModelProvider), DeviceModel.unknown);
    expect(
      container.read(presetLoadStatusProvider),
      contains('connection lost'),
    );
  });

  testWidgets('checkUsbLiveness disconnects when the USB port has vanished', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [transportKindProvider.overrideWith((_) => .usb)],
    );

    addTearDown(container.dispose);
    final ref = await pumpRef(tester, container);

    container.read(connectionStateProvider.notifier).state = true;
    container.read(connectedDeviceNameProvider.notifier).state = 'Smart Box';

    await checkUsbLiveness(ref, probe: (_) async => false);

    expect(container.read(connectionStateProvider), isFalse);
  });

  testWidgets(
    'checkUsbLiveness does NOT disconnect when enumeration is unavailable',
    (tester) async {
      final container = ProviderContainer(
        overrides: [transportKindProvider.overrideWith((_) => .usb)],
      );

      addTearDown(container.dispose);
      final ref = await pumpRef(tester, container);

      container.read(connectionStateProvider.notifier).state = true;
      container.read(connectedDeviceNameProvider.notifier).state = 'Smart Box';

      // null = couldn't enumerate — a transient hiccup must not false-trip.
      await checkUsbLiveness(ref, probe: (_) async => null);

      expect(container.read(connectionStateProvider), isTrue);
    },
  );

  testWidgets(
    'checkUsbLiveness keeps the connection while the port is present',
    (tester) async {
      final container = ProviderContainer(
        overrides: [transportKindProvider.overrideWith((_) => .usb)],
      );

      addTearDown(container.dispose);
      final ref = await pumpRef(tester, container);

      container.read(connectionStateProvider.notifier).state = true;
      container.read(connectedDeviceNameProvider.notifier).state = 'Smart Box';

      await checkUsbLiveness(ref, probe: (_) async => true);

      expect(container.read(connectionStateProvider), isTrue);
    },
  );

  testWidgets(
    'checkUsbLiveness is a no-op on BLE (even if the probe says gone)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [transportKindProvider.overrideWith((_) => .ble)],
      );

      addTearDown(container.dispose);
      final ref = await pumpRef(tester, container);

      container.read(connectionStateProvider.notifier).state = true;
      container.read(connectedDeviceNameProvider.notifier).state =
          'Smart Box BLE';

      await checkUsbLiveness(ref, probe: (_) async => false);

      expect(container.read(connectionStateProvider), isTrue);
    },
  );
}
