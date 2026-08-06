// Live hardware integration test — requires the Sonicake pedal connected.
// Run: flutter test integration_test/device_live_test.dart -d linux
//
// Drives the full Dart device stack (flutter_midir StreamSink -> reassembler ->
// classifier) against the real device, proving frb byte delivery end-to-end.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport_packages.dart';
import 'package:sonicmaster/protocol/inbound_message.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connect + query yields classified inbound messages', (
    tester,
  ) async {
    final service = DeviceService(MidiCommandTransport());

    await service.init();

    final received = <InboundMessage>[];
    final sub = service.inbound.listen(received.add);

    await service.connect();
    // Read-only global-settings request (8080 stripped for USB MIDI).
    await service.sendFrame('8080F00B0900010000000201020100F7');

    // Give the pedal time to reply (multi-packet dump).
    for (var i = 0; i < 20 && received.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    await sub.cancel();
    await service.disconnect();

    // Log what came back for the capture that Plan 5c will decode.
    for (final m in received) {
      // ignore: avoid_print
      print(
        'INBOUND ${m.runtimeType}'
        '${m is DataFrame ? ' ${m.hex}' : ''}'
        '${m is MalformedFrame ? ' ${m.hex}' : ''}',
      );
    }

    expect(
      received,
      isNotEmpty,
      reason: 'pedal sent no classified inbound messages',
    );
  });
}
