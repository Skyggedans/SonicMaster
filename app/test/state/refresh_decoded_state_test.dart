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

import '../fixtures/preset_state_dumps.dart';

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

/// Returns null for the first [failFirst] state-dump requests (simulating the
/// flaky 1s timeout under connect-time contention), then the real dump.
class _StateDumpSpy extends DeviceService {
  _StateDumpSpy(this.dump, {this.failFirst = 2}) : super(_NoopTransport());
  final String dump;
  final int failFirst;
  int calls = 0;

  @override
  Future<String?> requestStateDump({
    Duration timeout = const Duration(seconds: 1),
  }) async {
    calls++;

    return calls <= failFirst ? null : dump;
  }
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
  testWidgets('refreshDecodedState retries the flaky state dump before giving '
      'up, and decodes once it arrives', (tester) async {
    final data = await tester.runAsync(() => DataAssets.load());
    final service = _StateDumpSpy(u01StateDump, failFirst: 2);

    final container = ProviderContainer(
      overrides: [
        deviceServiceProvider.overrideWith((_) => service),
        dataAssetsProvider.overrideWith((ref) => data!),
      ],
    );

    addTearDown(container.dispose);
    final ref = await _pumpRef(tester, container);

    await container.read(dataAssetsProvider.future); // resolve valueOrNull

    await refreshDecodedState(ref);

    expect(service.calls, 3, reason: 'two timeouts, then success on the third');
    expect(
      container.read(currentSelectedEffectsProvider),
      isNotEmpty,
      reason: 'decoded after the retry instead of clearing to empty',
    );
  });

  testWidgets('refreshDecodedState clears when the dump never arrives', (
    tester,
  ) async {
    final data = await tester.runAsync(() => DataAssets.load());
    final service = _StateDumpSpy(u01StateDump, failFirst: 99);

    final container = ProviderContainer(
      overrides: [
        deviceServiceProvider.overrideWith((_) => service),
        dataAssetsProvider.overrideWith((ref) => data!),
      ],
    );

    addTearDown(container.dispose);
    final ref = await _pumpRef(tester, container);

    await container.read(dataAssetsProvider.future);

    // Seed a non-empty state so we can see it get cleared.
    container.read(currentSelectedEffectsProvider.notifier).state = {1: 101};
    await refreshDecodedState(ref);

    expect(service.calls, 3, reason: 'bounded to 3 attempts');
    expect(container.read(currentSelectedEffectsProvider), isEmpty);
  });
}
