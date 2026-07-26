// Live hardware gate — requires the Sonicake pedal connected.
// Run: flutter test integration_test/effect_toggle_test.dart -d linux
//
// Confirms 0407 (effect type) and 0409 (module on/off) apply on the device,
// then restores the preset so it is left tidy (edited-but-unsaved).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport_packages.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/preset_state_decoder.dart';
import 'package:sonicmaster/protocol/selected_effects_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('0407 effect change + 0409 module on/off apply', (tester) async {
    final service = DeviceService(MidiCommandTransport());

    await service.init();

    final data = await DataAssets.load();

    await service.connect();

    // Reads the live state dump via the production path (await + timeout),
    // returning (selectedEffects, moduleStates).
    Future<(Map<int, int>, Map<String, bool>)> readState() async {
      final dump = await service.requestStateDump();

      if (dump == null) {
        return (const <int, int>{}, const <String, bool>{});
      }

      return (
        SelectedEffectsDecoder(data.signatures).decode(dump),
        PresetStateDecoder(data.modules).decode(dump)?.moduleStates ?? const {},
      );
    }

    await service.sendAndAwaitAck(data.commands.presetSelect(.user, 1)!);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    await service.sendFrame(
      data.commands.effectType(2, 208)!,
    ); // DRV -> Red Fuzz
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final afterFx = await readState();

    await service.sendFrame(data.commands.moduleOff(1)!); // FX1 off
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final afterOff = await readState();

    // Restore so the preset is left as loaded (still edited-but-unsaved).
    await service.sendFrame(data.commands.effectType(2, 201)!);
    await service.sendFrame(data.commands.moduleOn(1)!);

    await service.disconnect();

    expect(afterFx.$1[2], 208, reason: '0407 should change DRV effect');
    expect(afterOff.$2['FX1'], false, reason: '0409 should turn FX1 off');
  });
}
