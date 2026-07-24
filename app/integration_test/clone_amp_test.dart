// Live gate — Clone amp (module 9 / User Profile) select + param edit.
// Enters clone on scratch U50, selects a profile + edits its Gain via the
// module-9 commands, reads them back, and restores.
// Run: flutter test integration_test/clone_amp_test.dart -d linux

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/device/transport_packages.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/param_value_key.dart';
import 'package:sonicmaster/protocol/parameter_values_decoder.dart';
import 'package:sonicmaster/protocol/selected_effects_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Clone amp (module 9) select + param edit', (tester) async {
    await initTransports();
    final service = DeviceService(MidiCommandTransport())..startListening();
    final data = await DataAssets.load();

    await service.connect();

    Future<(Map<int, int>, Map<int, Map<int, num>>)> read() async {
      final dump = await service.requestStateDump();

      if (dump == null) {
        return (const <int, int>{}, const <int, Map<int, num>>{});
      }

      final sel = SelectedEffectsDecoder(data.signatures).decode(dump);
      final params = ParameterValuesDecoder(
        data.parameters,
      ).decode(dump, sel, data.effects);

      return (sel, params);
    }

    await service.sendAndAwaitAck(data.commands.presetSelect(.user, 50)!);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Enter clone mode so module 9 is the active amp.
    await service.sendFrame(data.commands.ampClone);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Select User Profile 2 via the (now module-9-keyed) effect-type command.
    await service.sendFrame(data.commands.effectType(9, 902)!);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final (selA, _) = await read();

    // Edit the Clone Gain (module 9 algId 0).
    final target = (selA[9] == 902) ? 42 : 7;

    await service.sendFrame(
      data.commands.parameterCommand(9, 0, formatParamValueKey(target))!,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final (_, paramsB) = await read();

    // Restore: profile 1, factory amp.
    await service.sendFrame(data.commands.effectType(9, 901)!);
    await service.sendFrame(data.commands.ampFactory);
    await service.disconnect();

    expect(selA[9], 902, reason: 'effectType(9, 902) selects User Profile 2');
    expect(
      paramsB[9]?[0],
      target,
      reason: 'parameterCommand(9, 0) edits the Clone Gain',
    );
  });
}
