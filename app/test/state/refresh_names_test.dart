import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';

class _NoopTransport implements Transport {
  @override
  Stream<Uint8List> rawPackets() => const Stream<Uint8List>.empty();
  @override
  Future<void> connect({String? target}) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Stream<bool>? connectionEvents() => null;
  @override
  Future<void> sendFrame(String frameHex) async {}
}

/// Records whether the preset-names dump was requested, without touching the
/// real inbound stream (avoids stream/timer plumbing in the test).
class _SpyService extends DeviceService {
  _SpyService() : super(_NoopTransport());
  bool presetNamesRequested = false;

  @override
  Future<String?> requestPresetNames({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    presetNamesRequested = true;

    return null;
  }

  @override
  Future<String?> requestUserNames(
    String requestHex, {
    Duration timeout = const Duration(seconds: 1),
  }) async => null;
}

Future<WidgetRef> _pumpRef(
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

void main() {
  testWidgets('refreshNames requests names even when data assets resolve after connect '
      '(startup-race regression)', (tester) async {
    // Load real data outside the fake-async zone (rootBundle I/O never advances
    // inside it).
    final data = await tester.runAsync(() => DataAssets.load());
    final service = _SpyService();

    final container = ProviderContainer(
      overrides: [
        deviceServiceProvider.overrideWith((_) => service),
        // Resolve on a later microtask so `valueOrNull` is null at refreshNames'
        // first read — the exact startup auto-connect race that dropped names.
        // The old `valueOrNull` guard returned early here and never requested the
        // dump; the fix awaits `dataAssetsProvider.future` instead. (A microtask
        // resolves within the fake-async zone; a raw rootBundle load would not.)
        dataAssetsProvider.overrideWith((ref) => Future.microtask(() => data!)),
      ],
    );

    addTearDown(container.dispose);
    final ref = await _pumpRef(tester, container);

    await refreshNames(ref);

    expect(
      service.presetNamesRequested,
      isTrue,
      reason: 'preset-names dump should be requested once assets have loaded',
    );
  });
}
