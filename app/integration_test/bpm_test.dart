// Live hardware gate — requires the Sonicake pedal connected.
// Round-trips PRESET BPM on U01 through the app's own synthesized frame and the
// decoder, then restores it. Targets a value above 255 so the 16-bit high byte
// is exercised end to end (a one-byte path would truncate 260 -> 4).
// Run: flutter test integration_test/bpm_test.dart -d linux

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport_packages.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/preset_field_frame.dart';
import 'package:sonicmaster/protocol/preset_state_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('0402 preset BPM applies, 16-bit, via synthesized frame', (
    tester,
  ) async {
    final service = DeviceService(MidiCommandTransport());

    await service.init();

    final data = await DataAssets.load();

    await service.connect();

    Future<int?> readBpm() async {
      final dump = await service.requestStateDump();

      if (dump == null) return null;

      return PresetStateDecoder(data.modules).decode(dump)?.presetBpm;
    }

    Future<void> writeBpm(int v) => service.sendFrame(
      PresetFieldFrame.build(field: PresetFieldFrame.bpmField, value: v),
    );

    await service.sendAndAwaitAck(data.commands.presetSelect(.user, 1)!);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final before = await readBpm();

    expect(before, isNotNull, reason: 'decoded a preset BPM');

    // Always put the pedal back and disconnect, even if an expect below throws.
    addTearDown(() async {
      await writeBpm(before!);
      await service.disconnect();
    });

    // A value that needs the high byte (0x0104), different from the current one.
    final target = (before == 260) ? 200 : 260;

    await writeBpm(target);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final after = await readBpm();

    expect(after, target, reason: 'BPM $target must apply and read back 16-bit');
  });
}
