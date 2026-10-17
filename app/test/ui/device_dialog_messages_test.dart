import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/device_dialog.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

import '../support/sonic_host.dart';
import '../support/view_helpers.dart';

void main() {
  test('Android points at Chrome or Samsung Internet', () {
    for (final message in [
      webMidiUnsupportedMessage(.android),
      webBluetoothUnsupportedMessage(.android),
    ]) {
      expect(message, contains('Chrome or Samsung Internet'));
      expect(message, isNot(contains('Firefox')));
      expect(message, isNot(contains('chrome://flags')));
    }
  });

  test('iOS: no browser there can connect; no other browser is suggested', () {
    for (final message in [
      webMidiUnsupportedMessage(.iOS),
      webBluetoothUnsupportedMessage(.iOS),
    ]) {
      expect(message, contains('No iPhone or iPad browser can connect'));
      expect(message, isNot(contains('Bluefy')));
      expect(message, isNot(contains('Safari')));
    }
  });

  test('desktop Linux keeps the chrome://flags hint for Bluetooth', () {
    expect(
      webBluetoothUnsupportedMessage(.linux),
      'Web Bluetooth is not available.\n'
      'Use Chrome, Edge, or Opera. On Linux, enable\n'
      'chrome://flags/#enable-experimental-web-platform-features',
    );
  });

  test('other desktops: today\'s browser lists, no Linux flag', () {
    for (final platform in const <TargetPlatform>[.windows, .macOS]) {
      expect(
        webBluetoothUnsupportedMessage(platform),
        'Web Bluetooth is not available.\nUse Chrome, Edge, or Opera.',
      );
    }

    for (final platform in const <TargetPlatform>[.linux, .windows, .macOS]) {
      expect(
        webMidiUnsupportedMessage(platform),
        'Web MIDI is not available in this browser.\n'
        'Use Chrome, Edge, Opera, or Firefox.',
      );
    }
  });

  testWidgets('the longest message shows in full in a 568x320 phone picker', (
    tester,
  ) async {
    const size = Size(568, 320);

    final longest = [
      for (final platform in TargetPlatform.values) ...[
        webMidiUnsupportedMessage(platform),
        webBluetoothUnsupportedMessage(platform),
      ],
    ].reduce((a, b) => b.length > a.length ? b : a);

    final context = await pumpSonicHost(tester, size: size);

    unawaited(
      showSonicDialog<void>(
        context: context,
        builder: (_) => DeviceDialogShell(
          content: DeviceStateMessage(longest),
          transport: .usb,
          onTransport: (_) {},
          onRescan: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectNoOverflow(tester);

    final message = tester.getRect(find.text(longest));
    final area = tester.getRect(
      find
          .ancestor(
            of: find.text(longest),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );

    expectWithin(message, area, 'the message, unscrolled');
    expectWithin(message, Offset.zero & size, 'the message, on screen');
    expectWithin(
      tester.getRect(find.text('Cancel')),
      Offset.zero & size,
      'Cancel',
    );
  });
}
