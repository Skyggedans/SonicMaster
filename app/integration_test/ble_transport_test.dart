// Live BLE gate — requires the pedal advertising 'Smart Box BLE'.
// Proves the full app stack works over BLE: DeviceService(BleTransport) ->
// classifyInbound -> the real state decoder.
// Run: flutter test integration_test/ble_transport_test.dart -d linux

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/device/transport_factory.dart';
import 'package:sonicmaster/device/transport_packages.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/preset_state_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BLE transport round-trips through the real decoders', (
    tester,
  ) async {
    await initTransports();
    final service = DeviceService(UniversalBleTransport())..startListening();
    final data = await DataAssets.load();

    await service.connect(); // 'Smart Box BLE'

    await service.sendAndAwaitAck(data.commands.presetSelect(.user, 1)!);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final dump = await service.requestStateDump();

    await service.disconnect();

    expect(
      dump,
      isNotNull,
      reason: 'BLE state dump should arrive + reassemble',
    );
    final state = PresetStateDecoder(data.modules).decode(dump!);

    expect(state, isNotNull, reason: 'the BLE dump should decode');
    expect(state!.chainOrder.length, 9, reason: 'a full 9-module chain');
  });

  testWidgets('scan + connect to a picked BLE device', (tester) async {
    await initTransports();
    final devices = await enumerateBleDevices();

    expect(
      devices.any((d) => d.name == 'Smart Box BLE'),
      true,
      reason: 'the pedal should be discoverable',
    );

    final service = DeviceService(UniversalBleTransport())..startListening();
    final data = await DataAssets.load();

    await service.connect(target: 'Smart Box BLE'); // the picker's chosen name
    await service.sendAndAwaitAck(data.commands.presetSelect(.user, 1)!);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final dump = await service.requestStateDump();

    await service.disconnect();

    final state = PresetStateDecoder(data.modules).decode(dump!);

    expect(state?.chainOrder.length, 9);
  });
}
