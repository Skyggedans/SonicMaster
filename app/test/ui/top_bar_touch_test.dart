import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/ui/connection_controls.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/top_bar.dart';

import '../support/page_harness.dart';

void main() {
  const phone = Size(852, 393);

  final picker = find.text('Select a device');

  // The red dot: ConnectionControls' first item when it has no status label.
  Offset dot(WidgetTester tester) {
    final controls = tester.getRect(find.byType(ConnectionControls));

    return Offset(controls.left + 4, controls.center.dy);
  }

  // 3 px below the bar's top edge, in [target]'s column: outside the well
  // itself, inside the bar.
  Offset nearBarTop(WidgetTester tester, Finder target) => Offset(
    tester.getCenter(target).dx,
    tester.getRect(find.byType(TopBar)).top + 3,
  );

  Future<void> tapAndSettle(WidgetTester tester, Offset spot) async {
    await tester.tapAt(spot);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // the dialog fade
  }

  group('compact, disconnected: the whole well connects', () {
    testWidgets('a tap on the status dot opens the device picker', (
      tester,
    ) async {
      await pumpPage(tester, size: phone, isConnected: false);
      await tapAndSettle(tester, dot(tester));

      expect(picker, findsOneWidget);
    });

    testWidgets('a tap above the Connect button opens the picker', (
      tester,
    ) async {
      await pumpPage(tester, size: phone, isConnected: false);
      await tapAndSettle(tester, nearBarTop(tester, find.text('Connect')));

      expect(picker, findsOneWidget);
    });

    testWidgets('no picker while an auto-reconnect retry runs', (tester) async {
      await pumpPage(
        tester,
        size: phone,
        isConnected: false,
        overrides: [reconnectingProvider.overrideWith((_) => true)],
      );
      await tapAndSettle(tester, dot(tester));

      expect(picker, findsNothing);
    });
  });

  testWidgets('compact, connected: the glyph never disconnects', (
    tester,
  ) async {
    final container = await pumpPage(tester, size: phone);

    await tapAndSettle(tester, tester.getCenter(find.byIcon(Icons.usb)));

    // Per tap: the next one would dismiss a picker this one opened.
    expect(picker, findsNothing);

    await tapAndSettle(tester, nearBarTop(tester, find.text('Disconnect')));

    expect(container.read(connectionStateProvider), isTrue);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(picker, findsNothing);

    // The button itself still disconnects.
    await tapAndSettle(tester, tester.getCenter(find.text('Disconnect')));

    expect(container.read(connectionStateProvider), isFalse);
  });

  testWidgets('compact: the title-bar icons are 38x46 touch targets', (
    tester,
  ) async {
    await pumpPage(tester, size: phone);

    for (final icon in [
      Icons.tune,
      Icons.file_download,
      Icons.file_upload,
      Icons.save,
    ]) {
      expect(
        tester.getSize(find.widgetWithIcon(SonicIconButton, icon)),
        const Size(38, 46),
      );
    }
  });

  testWidgets('regular: only the Connect button connects (unchanged)', (
    tester,
  ) async {
    await pumpPage(tester, size: const Size(1280, 800), isConnected: false);
    await tapAndSettle(tester, dot(tester));

    // Per tap: the next one would dismiss a picker this one opened.
    expect(picker, findsNothing);

    await tapAndSettle(tester, nearBarTop(tester, find.text('Connect')));

    expect(picker, findsNothing);

    await tapAndSettle(tester, tester.getCenter(find.text('Connect')));

    expect(picker, findsOneWidget);
  });
}
