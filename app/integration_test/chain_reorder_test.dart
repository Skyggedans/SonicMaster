// Live hardware gate — requires the Sonicake pedal connected.
// Run: flutter test integration_test/chain_reorder_test.dart -d linux
//
// Confirms 0404 chain reorder applies on the device (amp block stays a
// contiguous [DRV,AMP,IR,EQ] unit), then restores the original order.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/model/chain_order.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/preset_state_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('0404 chain reorder applies', (tester) async {
    final service = DeviceService(UsbTransport());

    await service.init();

    final data = await DataAssets.load();

    await service.connect();

    Future<List<String>> readOrder() async {
      final dump = await service.requestStateDump();

      if (dump == null) return const [];

      return PresetStateDecoder(data.modules).decode(dump)?.chainOrder ??
          const [];
    }

    await service.sendAndAwaitAck(data.commands.presetSelect(.user, 1)!);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final original = await readOrder();

    expect(original.length, 9, reason: 'decoded a full 9-module chain');

    final groups = collapseChain(original);
    final target = flattenChain([...groups.sublist(1), groups.first]);
    final frame = data.commands.chainOrderCommand(target.join('-'));

    expect(frame, isNotNull, reason: 'rotated order must be a table key');

    await service.sendFrame(frame!);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = await readOrder();

    // Restore.
    final restore = data.commands.chainOrderCommand(original.join('-'));

    if (restore != null) await service.sendFrame(restore);

    await service.disconnect();

    expect(after, target, reason: '0404 should apply the rotated order');
    final i = after.indexOf('DRV');

    expect(
      after.sublist(i, i + 4),
      ampBlock,
      reason: 'amp block stays contiguous & ordered',
    );
  });
}
