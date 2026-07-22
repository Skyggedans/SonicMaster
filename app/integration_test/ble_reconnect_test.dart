// Live BLE connection-event plumbing gate.
// Verifies: a connect emits `true`; a user disconnect emits NO `false` (its
// monitor is aborted first, so it won't spuriously trigger auto-reconnect).
// The full unexpected-drop -> `false` -> auto-reconnect path needs a real drop
// (power off / move out of range) and is verified manually.
// Run: flutter test integration_test/ble_reconnect_test.dart -d linux

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BLE connect emits true; user disconnect emits no false', (
    tester,
  ) async {
    await initTransports();
    final service = DeviceService(BleTransport())..startListening();
    final events = <bool>[];
    final sub = service.connectionEvents!.listen(events.add);

    await service.connect(); // -> should emit true
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(events.contains(true), true, reason: 'connect should emit true');

    events.clear();
    await service.disconnect(); // user disconnect: monitor aborted -> no false

    for (final _ in Iterable<int>.generate(12)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    await sub.cancel();

    expect(
      events.contains(false),
      false,
      reason: 'a user disconnect must not emit a drop event',
    );
  });
}
