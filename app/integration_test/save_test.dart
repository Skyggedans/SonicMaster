// Live hardware gate — requires the Sonicake pedal connected.
// Writes ONLY to SCRATCH slot U50 (user-approved disposable).
// Run: flutter test integration_test/save_test.dart -d linux
//
// Confirms 040A save persists an edit to flash: edit a param, save to U50,
// reload (via another slot to flush live state), and read the stored value back.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/parameter_values_decoder.dart';
import 'package:sonicmaster/protocol/preset_name_codec.dart';
import 'package:sonicmaster/protocol/save_preset_frame.dart';
import 'package:sonicmaster/protocol/selected_effects_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('040A save persists a param to flash (scratch U50)', (
    tester,
  ) async {
    final service = DeviceService(UsbTransport());

    await service.init();

    final data = await DataAssets.load();

    await service.connect();

    Future<Map<int, Map<int, num>>> readParams() async {
      final dump = await service.requestStateDump();

      if (dump == null) return const {};

      final selected = SelectedEffectsDecoder(data.signatures).decode(dump);

      return ParameterValuesDecoder(
        data.parameters,
      ).decode(dump, selected, data.effects);
    }

    Future<void> loadU(int n) async {
      await service.sendAndAwaitAck(data.commands.presetSelect(.user, n)!);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    await loadU(50);
    final before = await readParams();
    final cur = before[2]?[0];
    final target = (cur == 42) ? 7 : 42;

    // Edit DRV (module 2) algId 0 -> target (0408).
    await service.sendFrame(data.commands.parameterCommand(2, 0, '$target')!);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Save to flash slot 50 (040A), await ACK, let the write settle.
    final saveFrame = SavePresetFrame(
      PresetNameCodec(data.characters),
    ).build(name: 'SONICMSTR', presetNumber: 50);

    final ack = await service.sendAndAwaitAck(saveFrame);

    await Future<void>.delayed(const Duration(milliseconds: 600));

    // Flush live state (load U01) then reload U50 -> reads STORED state.
    await loadU(1);
    await loadU(50);
    final stored = await readParams();

    await service.disconnect();

    expect(ack, true, reason: '040A save should be ACKed');
    expect(
      stored[2]?[0],
      target,
      reason: '040A should persist the edited param to flash',
    );
  });
}
