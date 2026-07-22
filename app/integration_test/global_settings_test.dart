// Live hardware gate — requires the Sonicake pedal connected.
// Round-trips only inputLevel (set 5 -> read -> restore 0), the value it
// started at on this device. Run: flutter test integration_test/global_settings_test.dart -d linux

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/global_settings_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('global settings decode + inputLevel round-trip', (tester) async {
    final service = DeviceService(UsbTransport());

    await service.init();

    final data = await DataAssets.load();

    await service.connect();

    Future<int?> readInput() async {
      final dump = await service.requestGlobalSettings();

      if (dump == null) return null;

      return const GlobalSettingsDecoder().decode(dump)?.inputLevel;
    }

    final before = await readInput();

    expect(before, isNotNull, reason: 'global settings should decode');

    await service.sendFrame(data.commands.globalCommand('inputLevel', 5)!);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = await readInput();

    // Restore inputLevel to 0 (its value on this device).
    await service.sendFrame(data.commands.globalCommand('inputLevel', 0)!);
    await service.disconnect();

    expect(after, 5, reason: '0101 inputLevel applies + reads back');
  });
}
