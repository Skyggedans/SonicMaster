// Live gate: fetch + decode the pedal's names over USB. Run with the pedal
// connected: flutter test integration_test/names_gate_test.dart -d linux
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/protocol/name_dump_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('names decode from the live pedal', (tester) async {
    await initTransports();
    final service = DeviceService(UsbTransport());

    service.startListening();
    await service.connect(target: 'Smart Box');
    final data = await DataAssets.load();

    final presetDump = await service.requestPresetNames();

    expect(presetDump, isNotNull, reason: 'no preset-names dump');
    final names = decodePresetNames(presetDump!, data.characters);

    expect(names.length, greaterThan(0));
    // ignore: avoid_print
    print(
      'GATE preset: ${names.length} names, '
      'U01="${names[const PresetRef(.user, 1)]}"',
    );

    final clone = await service.requestUserNames(
      DeviceService.cloneNamesRequest,
    );

    expect(clone, isNotNull, reason: 'no clone-names dump');
    final profiles = decodeUserNames(
      clone!,
      data.characters,
      fallbackPrefix: 'User Profile',
    );

    expect(profiles.length, 5);

    final ir = await service.requestUserNames(DeviceService.irNamesRequest);

    expect(ir, isNotNull, reason: 'no ir-names dump');
    final irs = decodeUserNames(
      ir!,
      data.characters,
      fallbackPrefix: 'User IR',
    );

    expect(irs.length, 5);
    // ignore: avoid_print
    print('GATE profiles=$profiles ir=$irs');

    await service.dispose();
  });
}
