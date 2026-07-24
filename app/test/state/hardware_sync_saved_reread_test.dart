import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/inbound_message.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/hardware_sync.dart';
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

/// Records state-dump requests and always answers with [dump].
class _StateDumpSpy extends DeviceService {
  _StateDumpSpy(this.dump) : super(_NoopTransport());

  final String dump;
  int calls = 0;

  @override
  Future<String?> requestStateDump({
    Duration timeout = const Duration(seconds: 1),
  }) async {
    calls++;

    return dump;
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
  // Regression: an on-pedal edit that returns the preset to its saved value
  // clears the pedal's dirty flag, so the pedal broadcasts "saved" (…050000)
  // rather than "modified" (…050001). handleHardwareSync used to ignore it, so
  // the UI kept the pre-edit state — the "toggle a module off, then on, and its
  // indicator never lights up again" bug. It must re-read on "saved" too.
  testWidgets(
    'a device "saved" notify re-reads state and clears the dirty flag',
    (tester) async {
      final data = await tester.runAsync(DataAssets.load);
      final service = _StateDumpSpy(u01StateDump);

      final container = ProviderContainer(
        overrides: [
          deviceServiceProvider.overrideWith((_) => service),
          dataAssetsProvider.overrideWith((ref) => data!),
        ],
      );

      addTearDown(container.dispose);
      final ref = await _pumpRef(tester, container);
      await container.read(dataAssetsProvider.future); // resolve valueOrNull

      // Stale UI left by a prior on-pedal edit: empty selection, still dirty.
      container.read(currentSelectedEffectsProvider.notifier).state = const {};
      container.read(presetModifiedProvider.notifier).state = true;

      handleHardwareSync(ref, const PresetSavedMessage());

      expect(
        container.read(presetModifiedProvider),
        isFalse,
        reason: 'a saved notify clears the dirty flag',
      );

      // Let the debounced re-read fire and complete.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        service.calls,
        greaterThan(0),
        reason:
            'a saved notify must trigger a state re-read (the bug: it did not)',
      );
      expect(
        container.read(currentSelectedEffectsProvider),
        isNotEmpty,
        reason: 're-read decoded the device state back into the UI',
      );
    },
  );
}
