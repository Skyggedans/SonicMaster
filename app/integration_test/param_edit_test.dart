// Live hardware gate for the write path — requires the Sonicake pedal connected.
// Run: flutter test integration_test/param_edit_test.dart -d linux
//
// Loads U01, sets DRV Gain (module 2, algId 0) to 99 via a 0408 command, and
// confirms: the device emits PresetModified, and a re-read shows the new value.
// (Leaves the preset edited-but-unsaved; reloading restores it.)

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport_packages.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/inbound_message.dart';
import 'package:sonicmaster/protocol/parameter_values_decoder.dart';
import 'package:sonicmaster/protocol/selected_effects_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editing a parameter (0408) applies on the device', (
    tester,
  ) async {
    final service = DeviceService(MidiCommandTransport());

    await service.init();

    final data = await DataAssets.load();
    final received = <InboundMessage>[];
    final sub = service.inbound.listen(received.add);

    await service.connect();

    await service.sendAndAwaitAck(data.commands.presetSelect(.user, 1)!);
    // Settle: a param command sent mid-load is dropped by the device.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Edit DRV Gain -> 99 and watch for the modified notification.
    received.clear();
    await service.sendFrame(data.commands.parameterCommand(2, 0, '99')!);

    for (final _ in Iterable<int>.generate(8)) {
      await tester.pump(const Duration(milliseconds: 80));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    final sawModified = received.any((m) => m is PresetModifiedMessage);

    // Re-read and decode.
    received.clear();
    await service.sendFrame('8080F0000900010000000201020401F7');

    for (final _ in Iterable<int>.generate(14)) {
      await tester.pump(const Duration(milliseconds: 80));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    final dumps = received.whereType<DataFrame>().map((f) => f.hex).toList();
    final fx = dumps.isEmpty
        ? <int, int>{}
        : SelectedEffectsDecoder(data.signatures).decode(dumps.first);

    final params = dumps.isEmpty
        ? <int, Map<int, num>>{}
        : ParameterValuesDecoder(
            data.parameters,
          ).decode(dumps.first, fx, data.effects);

    await sub.cancel();
    await service.disconnect();

    // ignore: avoid_print
    print('sawModified=$sawModified, DRV params=${params[2]}');
    expect(
      sawModified,
      isTrue,
      reason: 'expected a PresetModified notification',
    );
    expect(params[2]?[0], 99, reason: 'DRV Gain should read back as 99');
  });
}
