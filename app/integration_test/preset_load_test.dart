// Live hardware integration test — requires the Sonicake pedal connected.
// Run: flutter test integration_test/preset_load_test.dart -d linux
//
// Loads presets via the 0403 select command and observes the ACK + any
// preset-state dumps the device returns (captured for Plan 5c).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/protocol/inbound_message.dart';
import 'package:sonicmaster/protocol/parameter_values_decoder.dart';
import 'package:sonicmaster/protocol/preset_state_decoder.dart';
import 'package:sonicmaster/protocol/selected_effects_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loading a preset is ACKed and/or returns state dumps', (
    tester,
  ) async {
    final service = DeviceService(UsbTransport());

    await service.init();
    final data = await DataAssets.load();

    final received = <InboundMessage>[];
    final sub = service.inbound.listen(received.add);

    await service.connect();

    const presets = [PresetRef(.user, 1), PresetRef(.user, 2)];

    // Request the current preset's full state dump after selecting it.
    const stateRequest = '8080F0000900010000000201020401F7';

    var anyAck = false;
    var anyInbound = false;

    for (final preset in presets) {
      final frame = data.commands.presetSelect(preset.bank, preset.number)!;
      final ok = await service.sendAndAwaitAck(frame);

      anyAck = anyAck || ok;

      // Now ask for the full preset-state dump (Plan 5c decoder input).
      received.clear();
      await service.sendFrame(stateRequest);

      for (final _ in Iterable<int>.generate(12)) {
        await tester.pump(const Duration(milliseconds: 80));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }

      anyInbound = anyInbound || received.isNotEmpty;

      // Decode state (5c-1) + selected effects (5c-2) against fresh data.
      final dumps = received.whereType<DataFrame>().map((f) => f.hex).toList();
      final decoded = dumps.isEmpty
          ? null
          : PresetStateDecoder(data.modules).decode(dumps.first);

      final fx = dumps.isEmpty
          ? <int, int>{}
          : SelectedEffectsDecoder(data.signatures).decode(dumps.first);

      final fxNames = {
        for (final e in fx.entries)
          data.modules.nameOf(e.key): data.effects.byId(e.value)?.name,
      };

      // Parameter values (5c-3).
      final pv = dumps.isEmpty
          ? <int, Map<int, num>>{}
          : ParameterValuesDecoder(
              data.parameters,
            ).decode(dumps.first, fx, data.effects);

      // ignore: avoid_print
      print(
        '=== ${preset.label}: ack=$ok, '
        'decoded=${decoded == null ? 'null' : 'vol ${decoded.presetVolume}'}, '
        'effects=$fxNames, params=$pv ===',
      );
    }

    await sub.cancel();
    await service.disconnect();

    // Relaxed gate: some commands are fire-and-forget. Require an ACK or at
    // least one inbound frame after a select.
    expect(
      anyAck || anyInbound,
      isTrue,
      reason: 'no ACK and no inbound after preset select',
    );
  });
}
