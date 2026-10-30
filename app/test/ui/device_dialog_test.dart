import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/ui/device_dialog.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

import '../support/sonic_host.dart';
import '../support/view_helpers.dart';

void main() {
  // [isRescanEnabled] false is the web Bluetooth picker: the browser scans.
  Future<void> openShell(
    WidgetTester tester,
    Widget content, {
    required Size size,
    double keyboard = 0,
    TransportKind transport = .usb,
    bool isRescanEnabled = true,
  }) async {
    final context = await pumpSonicHost(tester, size: size, keyboard: keyboard);

    unawaited(
      showSonicDialog<void>(
        context: context,
        builder: (_) => DeviceDialogShell(
          content: content,
          transport: transport,
          onTransport: (_) {},
          onRescan: isRescanEnabled ? () {} : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget deviceList() => ListView(
    padding: EdgeInsets.zero,
    children: [
      for (final i in Iterable<int>.generate(8))
        SizedBox(height: 64, child: Text('Pedal $i')),
    ],
  );

  // The picker's own scroll view (the fallback below its minimum height).
  ScrollPosition shellScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(DeviceDialogShell),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets('regular: the device list keeps its 300 px', (tester) async {
    await openShell(tester, deviceList(), size: const Size(1280, 800));

    expect(tester.getSize(find.byType(ListView)).height, 300);
    expect(shellScroll(tester).maxScrollExtent, 0);
  });

  for (final size in const [
    Size(852, 393),
    Size(780, 360),
    Size(640, 300),
    Size(740, 280),
    Size(568, 320),
  ]) {
    final where = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('$where: Rescan and Cancel stay on screen, the list flexes', (
      tester,
    ) async {
      await openShell(tester, deviceList(), size: size);

      final screen = Offset.zero & size;

      expect(tester.takeException(), isNull);
      expectWithin(tester.getRect(find.text('Rescan')), screen, 'Rescan');
      expectWithin(tester.getRect(find.text('Cancel')), screen, 'Cancel');
      expect(tester.getSize(find.byType(ListView)).height, lessThan(300));
      expect(shellScroll(tester).maxScrollExtent, 0); // nothing else scrolls
    });
  }

  // On a plain landscape phone tab only the web Bluetooth explanation gives
  // way: its button, the only way on, shows and takes a tap with no
  // scrolling first.
  for (final size in const [
    Size(915, 332),
    Size(568, 320),
    Size(640, 300),
    Size(780, 290),
    Size(740, 280),
  ]) {
    final where = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('$where: the web Bluetooth button shows and takes a tap', (
      tester,
    ) async {
      var taps = 0;

      await openShell(
        tester,
        WebBleChooser(onSelect: () => taps++),
        size: size,
        transport: .ble,
        isRescanEnabled: false,
      );

      final select = find.text('Select Bluetooth device');

      expect(tester.takeException(), isNull);
      expect(select.hitTestable(), findsOneWidget);

      await tester.tap(select);
      await tester.pump();

      expect(taps, 1);
      expectWithin(
        tester.getRect(find.text('Cancel')),
        Offset.zero & size,
        'Cancel',
      );
    });
  }

  testWidgets('regular: the web Bluetooth button keeps its place (unchanged)', (
    tester,
  ) async {
    await openShell(
      tester,
      WebBleChooser(onSelect: () {}),
      size: const Size(1280, 800),
      transport: .ble,
      isRescanEnabled: false,
    );

    expect(
      tester.getRect(find.text('Select Bluetooth device')),
      rectMoreOrLessEquals(
        const Rect.fromLTRB(545.7, 467.5, 734.3, 490.5),
        epsilon: 0.1,
      ),
    );
  });

  testWidgets('a long state message fits a 740x280 phone', (tester) async {
    const size = Size(740, 280);

    await openShell(
      tester,
      const DeviceStateMessage(
        'Web Bluetooth is not available.\n'
        'Use Chrome, Edge, or Opera. On Linux, enable\n'
        'chrome://flags/#enable-experimental-web-platform-features',
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expectWithin(
      tester.getRect(find.text('Cancel')),
      Offset.zero & size,
      'Cancel',
    );
  });

  testWidgets('a keyboard still up scrolls the whole picker instead', (
    tester,
  ) async {
    // Connect tapped while a field had focus: the keyboard is still closing.
    const visible = Rect.fromLTWH(0, 0, 740, 280 - 180);

    await openShell(
      tester,
      deviceList(),
      size: const Size(740, 280),
      keyboard: 180,
    );

    expect(tester.takeException(), isNull);
    expect(shellScroll(tester).maxScrollExtent, greaterThan(0));

    await tester.ensureVisible(find.text('Cancel'));
    await tester.pumpAndSettle();

    expectWithin(tester.getRect(find.text('Cancel')), visible, 'Cancel');
  });
}
