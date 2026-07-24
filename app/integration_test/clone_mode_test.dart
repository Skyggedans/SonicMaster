// Live hardware gate — requires the Sonicake pedal connected.
// Toggles amp mode on U50 (live-only) and restores Factory.
// Run: flutter test integration_test/clone_mode_test.dart -d linux

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport_packages.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/preset_state_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ampClone/ampFactory toggle isCloneMode', (tester) async {
    final service = DeviceService(MidiCommandTransport());

    await service.init();

    final data = await DataAssets.load();

    await service.connect();

    Future<bool?> readClone() async {
      final dump = await service.requestStateDump();

      if (dump == null) return null;

      return PresetStateDecoder(data.modules).decode(dump)?.isCloneMode;
    }

    await service.sendAndAwaitAck(data.commands.presetSelect(.user, 50)!);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    bool? inClone;
    bool? inFactory;

    try {
      await service.sendFrame(data.commands.ampClone);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      inClone = await readClone();

      await service.sendFrame(data.commands.ampFactory);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      inFactory = await readClone();
    } finally {
      // Always leave the pedal in Factory, even if a read above threw.
      await service.sendFrame(data.commands.ampFactory);
      await service.disconnect();
    }

    expect(inClone, true, reason: 'ampClone sets isCloneMode');
    expect(inFactory, false, reason: 'ampFactory clears isCloneMode');
  });
}
