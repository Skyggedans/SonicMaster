import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/model/global_settings.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/global_settings_dialog.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

import '../support/silent_transport.dart';
import '../support/sonic_host.dart';
import '../support/test_assets.dart';
import '../support/view_helpers.dart';

void main() {
  final assets = loadTestDataAssets();

  // Opens the Settings dialog over a silent pedal; returns its transport (the
  // frames a knob or switch sends).
  Future<SilentTransport> openSettings(
    WidgetTester tester, {
    required Size size,
  }) async {
    final transport = SilentTransport();
    final context = await pumpSonicHost(
      tester,
      size: size,
      overrides: [
        dataAssetsProvider.overrideWith((_) => assets),
        deviceServiceProvider.overrideWith((ref) {
          final service = DeviceService(transport)..startListening();

          ref.onDispose(service.dispose);

          return service;
        }),
        globalSettingsProvider.overrideWith(
          (_) => const GlobalSettings(
            globalVolume: 50,
            inputLevel: 0,
            fxRecLevel: 0,
            monitorLevel: 0,
            btRecLevel: 0,
          ),
        ),
      ],
    );

    unawaited(
      showSonicDialog<void>(
        context: context,
        builder: (_) => const GlobalSettingsDialog(),
      ),
    );
    await tester.pumpAndSettle();

    return transport;
  }

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(GlobalSettingsDialog), matching: finder);

  // The dialog's scroll views, outermost first: SonicDialog's, then the
  // settings list's.
  List<ScrollPosition> scrolls(WidgetTester tester) => tester
      .stateList<ScrollableState>(inDialog(find.byType(Scrollable)))
      .map((state) => state.position)
      .toList();

  for (final size in const [
    Size(852, 393),
    Size(780, 360),
    Size(640, 300),
    Size(740, 280),
    Size(568, 320),
  ]) {
    final where = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('$where: title, settings and Close scroll as one list', (
      tester,
    ) async {
      await openSettings(tester, size: size);

      final [dialog, list, ...] = scrolls(tester);

      expect(tester.takeException(), isNull);
      expect(dialog.maxScrollExtent, greaterThan(0));
      expect(list.maxScrollExtent, 0); // uncapped: a passthrough

      await tester.ensureVisible(find.text('Close'));
      await tester.pumpAndSettle();

      expectWithin(
        tester.getRect(find.text('Close')),
        Offset.zero & size,
        'Close',
      );
    });
  }

  testWidgets('568x320: a level being typed stays above the keyboard', (
    tester,
  ) async {
    const size = Size(568, 320);
    const visible = Rect.fromLTWH(0, 0, 568, 320 - 180);

    await openSettings(tester, size: size);

    final readout = tester.getCenter(find.text('0 dB').first); // Input

    await tester.tapAt(readout);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(readout);
    await tester.pump();
    await setKeyboard(tester, 180);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expectWithin(
      tester.getRect(find.byType(EditableText)),
      visible,
      'the level field',
    );

    await tester.ensureVisible(find.text('Close'));
    await tester.pumpAndSettle();

    expectWithin(tester.getRect(find.text('Close')), visible, 'Close');
  });

  // A phone user flicks the Settings list upward and the flick starts on a
  // level knob: the list must scroll, and no live level may change.
  testWidgets('568x320: a flick that starts on a level knob scrolls', (
    tester,
  ) async {
    final transport = await openSettings(tester, size: const Size(568, 320));
    final gesture = await tester.startGesture(
      tester.getCenter(inDialog(find.byKey(const Key('knob'))).first),
    );

    for (final _ in Iterable<int>.generate(6)) {
      await gesture.moveBy(const Offset(0, -10));
    }

    await gesture.up();
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GlobalSettingsDialog)),
    );

    expect(scrolls(tester).first.pixels, greaterThan(0));
    expect(transport.sentFrames, isEmpty);
    expect(container.read(globalSettingsProvider)!.inputLevel, 0);
  });

  for (final (size, list, close) in const [
    (Size(1280, 800), 496.0, Rect.fromLTRB(731, 653, 835, 697)),
    (Size(960, 640), 396.8, Rect.fromLTRB(571, 523.4, 675, 567.4)),
  ]) {
    final where = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('regular $where: the list keeps its 62% cap, Close pinned', (
      tester,
    ) async {
      await openSettings(tester, size: size);

      final [dialog, settings, ...] = scrolls(tester);

      expect(settings.viewportDimension, closeTo(list, 0.01));
      expect(settings.maxScrollExtent, greaterThan(0));
      expect(dialog.maxScrollExtent, 0); // SonicDialog's scroll stays inert
      expect(
        tester.getRect(find.widgetWithText(SonicButton, 'Close')),
        rectMoreOrLessEquals(close),
      );
    });
  }

  for (final (size, eco) in const [
    (Size(852, 393), 1), // compact: the whole row is the switch
    (Size(1280, 800), 0), // regular: only the toggle (unchanged)
  ]) {
    final mode = eco == 1 ? 'compact' : 'regular';

    testWidgets('$mode: tapping the ECO label toggles ECO: ${eco == 1}', (
      tester,
    ) async {
      final transport = await openSettings(tester, size: size);
      final label = find.text('ECO');

      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      await tester.tap(label);
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(GlobalSettingsDialog)),
      );

      expect(container.read(globalSettingsProvider)!.eco, eco);
      expect(transport.sentFrames, hasLength(eco));
    });
  }
}
