// Live gate for G6. A solicited state-dump response must route through the real
// device and classify as a StateDump — proving the live inbound path and the
// classifier's StateDump branch on hardware. The PresetSelected branch
// (physical footswitch) is covered by test/state/hardware_sync_test.dart, which
// asserts on the exact bytes a physical preset change broadcasts (captured live
// during grounding).
//
// Run connected: flutter test integration_test/hwsync_gate_test.dart -d linux
// Verify by the printed `HWGATE: stateDumps=<n>` line (n >= 1 = live path OK).
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/device/transport_packages.dart';
import 'package:sonicmaster/protocol/inbound_message.dart';
import 'package:sonicmaster/protocol/multi_packet_reassembler.dart';
import 'package:sonicmaster/state/hardware_sync.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a device state dump classifies as StateDump (live)', (
    tester,
  ) async {
    final Transport transport = MidiCommandTransport();
    final reassembler = MultiPacketReassembler();

    var stateDumps = 0;

    // Same steps classifyInbound performs, inlined so cancel is synchronous.
    final sub = transport.rawPackets().listen((message) {
      if (message.length < 7 || message.first != 0xF0) return;

      String? frameHex;

      try {
        frameHex = reassembler.addPacket(message);
      } catch (_) {
        return;
      }

      if (frameHex == null) return;

      if (classifyHardwareSync(InboundMessage.classify(frameHex))
          is StateDump) {
        stateDumps++;
      }
    });

    await transport.connect(target: 'Smart Box');

    // Request a state dump (stored 8080-led; the transport strips the header).
    // The reassembled response carries the 01020401 signature → StateDump.
    await transport.sendFrame('8080F0000900010000000201020401F7');

    for (final _ in Iterable<int>.generate(25)) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // ignore: avoid_print
    print('HWGATE: stateDumps=$stateDumps');

    await sub.cancel();
    await transport.disconnect();

    expect(
      stateDumps,
      greaterThan(0),
      reason:
          'no StateDump classified from a solicited state request — '
          'the live device->classify path is broken',
    );
  });
}
