// Live hardware gate — requires the Sonicake pedal connected.
// Touches only PRESET volume on U01 (live-only; restored after). Global/master
// volume is a persistent device-global with no read-back, so it is not tested
// here (it was probe-verified live).
// Run: flutter test integration_test/volume_test.dart -d linux

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/preset_state_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('0402 preset volume applies (dump read-back)', (tester) async {
    final service = DeviceService(UsbTransport());

    await service.init();

    final data = await DataAssets.load();

    await service.connect();

    Future<int?> readPresetVol() async {
      final dump = await service.requestStateDump();

      if (dump == null) return null;

      return PresetStateDecoder(data.modules).decode(dump)?.presetVolume;
    }

    await service.sendAndAwaitAck(data.commands.presetSelect(.user, 1)!);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final before = await readPresetVol();

    expect(before, isNotNull, reason: 'decoded a preset volume');
    final target = (before == 42) ? 55 : 42;

    await service.sendFrame(
      data.commands.globalCommand('presetVolume', target)!,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = await readPresetVol();

    // Restore the original preset volume.
    final restore = data.commands.globalCommand('presetVolume', before!);

    if (restore != null) await service.sendFrame(restore);

    await service.disconnect();

    expect(after, target, reason: '0402 should apply the new preset volume');
  });
}
