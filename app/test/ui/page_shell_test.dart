import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/connection_controls.dart';
import 'package:sonicmaster/ui/global_settings_dialog.dart';
import 'package:sonicmaster/ui/preset_rail.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';
import 'package:sonicmaster/ui/top_bar.dart';
import 'package:sonicmaster/ui/window_controls.dart';

import '../support/fonts.dart';
import '../support/page_harness.dart';
import '../support/silent_transport.dart';

Finder _inBar(Finder finder) =>
    find.descendant(of: find.byType(TopBar), matching: finder);

/// The app-level horizontal scroll view (the first rightward Scrollable).
Finder get _appScroll => find
    .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == .right)
    .first;

/// A pedal whose every send stays in flight until the test completes it.
class _PendingTransport implements Transport {
  final _packets = StreamController<Uint8List>.broadcast();

  /// One completer per [sendFrame] call, in order.
  final pending = <Completer<void>>[];

  @override
  Stream<Uint8List> rawPackets() => _packets.stream;

  @override
  Future<void> connect({String? target}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendFrame(String frameHex) {
    final send = Completer<void>();

    pending.add(send);

    return send.future;
  }

  @override
  Stream<bool>? connectionEvents() => null;
}

void main() {
  group('regular title bar', () {
    for (final size in const [Size(1280, 800), Size(960, 640)]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('$label: 60 tall, logo zone over the rail, full well', (
        tester,
      ) async {
        await pumpPage(tester, size: size);

        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(TopBar)), Size(size.width, 60));

        final logoZone = find
            .ancestor(
              of: _inBar(find.byType(SonicLogo)),
              matching: find.byType(Container),
            )
            .first;

        // As wide as the rail, inside the plate's 1-px top and bottom edges.
        expect(tester.getRect(logoZone), const Rect.fromLTRB(0, 1, 244, 59));
        expect(tester.getRect(find.byType(PresetRail)).left, 0);
        expect(tester.getRect(find.byType(PresetRail)).width, railWidth);
        expect(_inBar(find.text('P01')), findsOneWidget);
        expect(_inBar(find.text('Clean')), findsOneWidget);
        // kDebugMode is true under flutter test: the console toggle shows.
        expect(_inBar(find.byIcon(Icons.terminal)), findsOneWidget);
        expect(_inBar(find.byType(ConnectionControls)), findsOneWidget);
        expect(_inBar(find.text('Smart Box')), findsOneWidget);
        expect(_inBar(find.text('Disconnect')), findsOneWidget);
        expect(find.byType(WindowControls), findsNothing);
      });
    }

    testWidgets('tune opens Settings while connected', (tester) async {
      await pumpPage(tester, size: const Size(1280, 800));
      await tester.tap(_inBar(find.byIcon(Icons.tune)));
      await tester.pumpAndSettle();

      expect(find.byType(GlobalSettingsDialog), findsOneWidget);

      // tune also re-reads the global settings: the silent pedal lets that
      // 1-s read time out (one real turn ends the wait, see silent_transport).
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() async {});
      await tester.pump();
    });

    testWidgets('disconnected: no preset well, the actions do nothing', (
      tester,
    ) async {
      await pumpPage(tester, size: const Size(1280, 800), isConnected: false);
      await tester.tap(_inBar(find.byIcon(Icons.tune)));
      await tester.tap(_inBar(find.byIcon(Icons.save)));
      await tester.pumpAndSettle();

      expect(find.byType(GlobalSettingsDialog), findsNothing);
      expect(_inBar(find.text('P01')), findsNothing);
      expect(_inBar(find.text('Disconnected')), findsOneWidget);
      expect(_inBar(find.text('Connect')), findsOneWidget);
    });

    testWidgets(
      'desktop windows keep their window controls in the bar',
      (tester) async {
        const channel = MethodChannel('window_manager');

        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'isMaximized' ? false : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await pumpPage(tester, size: const Size(1280, 800));

        expect(_inBar(find.byType(WindowControls)), findsOneWidget);
        expect(tester.getSize(find.byType(TopBar)), const Size(1280, 60));
      },
      variant: TargetPlatformVariant.desktop(),
    );
  });

  // The compact page tests keep the editor empty (selectedEffects: {}): the
  // work-area components keep their regular density until the density tasks,
  // so only the frame is pinned here.
  group('compact frame', () {
    for (final size in const [
      Size(852, 393),
      Size(640, 360),
      Size(568, 320),
      Size(1280, 500),
    ]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('$label: 48-px bar, burger slot, no logo, rail or console', (
        tester,
      ) async {
        await pumpPage(tester, size: size, selectedEffects: const {});

        expect(tester.takeException(), isNull);

        final appWidth = math.max(size.width, 640.0);
        final presetWell = find
            .ancestor(
              of: _inBar(find.text('P01')),
              matching: find.byType(SonicRecess),
            )
            .first;

        expect(tester.getSize(find.byType(TopBar)), Size(appWidth, 48));
        expect(_inBar(find.byType(SonicLogo)), findsNothing);
        expect(find.byType(PresetRail), findsNothing);
        expect(_inBar(find.byIcon(Icons.terminal)), findsNothing);
        // The leading slot stays empty: the drawer floats its burger there.
        expect(tester.getRect(presetWell).left, drawerButtonSlotWidth);
        expect(_inBar(find.text('Clean')), findsOneWidget);
        // The connection well drops the device name, keeps glyph + button.
        expect(_inBar(find.text('Smart Box')), findsNothing);
        expect(_inBar(find.byIcon(Icons.usb)), findsOneWidget);
        expect(
          tester.getRect(_inBar(find.text('Disconnect'))).right,
          lessThanOrEqualTo(appWidth - 8),
        );
      });
    }

    testWidgets('568x320 lays the app out 640 wide and scrolls it sideways', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(568, 320),
        names: {const PresetRef(.user, 1): 'WWWWWWWWWW'},
        selectedEffects: const {},
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(TopBar)), const Size(640, 48));
      expect(
        tester.state<ScrollableState>(_appScroll).position.maxScrollExtent,
        72,
      );
      // The longest preset name (10 characters) fits beside the actions.
      expect(
        tester.getRect(_inBar(find.text('WWWWWWWWWW'))).right,
        lessThanOrEqualTo(tester.getRect(_inBar(find.byIcon(Icons.tune))).left),
      );
    });

    testWidgets('a viewport the app fits never scrolls sideways', (
      tester,
    ) async {
      await pumpPage(tester, size: const Size(1280, 800));

      final scroll = tester.widget<Scrollable>(_appScroll);

      expect(scroll.physics, isA<NeverScrollableScrollPhysics>());
      expect(
        tester.state<ScrollableState>(_appScroll).position.maxScrollExtent,
        0,
      );
    });

    testWidgets('568x320 disconnected: red dot and Connect, no label', (
      tester,
    ) async {
      await pumpPage(tester, size: const Size(568, 320), isConnected: false);

      expect(tester.takeException(), isNull);
      expect(_inBar(find.text('Connect')), findsOneWidget);
      expect(_inBar(find.text('Disconnected')), findsNothing);
      expect(find.text('No device connected'), findsOneWidget);
    });

    testWidgets('mode flips keep the title bar and connection well elements', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(1280, 800),
        selectedEffects: const {},
      );

      final bar = tester.element(find.byType(TopBar));
      final well = tester.element(find.byType(ConnectionControls));

      // Regular -> compact -> below the compact minimum (the sideways scroll
      // turns on) -> regular again.
      for (final size in const [
        Size(852, 393),
        Size(393, 852),
        Size(568, 320),
        Size(1280, 800),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();

        expect(tester.takeException(), isNull, reason: '$size');
        expect(tester.element(find.byType(TopBar)), same(bar), reason: '$size');
        expect(
          tester.element(find.byType(ConnectionControls)),
          same(well),
          reason: '$size',
        );
      }
    });

    // Browser text at 200% on a phone: the well, not the bar, gives way. The
    // bar alone at the compact minimum width, so nothing else can mask it.
    testWidgets(
      'large text: the preset name ellipsizes instead of overflowing',
      (tester) async {
        await loadOswald();

        final container = ProviderContainer(
          overrides: [
            connectionStateProvider.overrideWith((_) => true),
            currentPresetProvider.overrideWith(
              (_) => const PresetRef(.user, 1),
            ),
            presetNamesProvider.overrideWith(
              (_) => {const PresetRef(.user, 1): 'WWWWWWWWWW'},
            ),
          ],
        );

        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Directionality(
                textDirection: .ltr,
                child: SonicMetricsScope(
                  metrics: SonicMetrics.compact,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 640,
                      child: TopBar(
                        isConsoleOpen: false,
                        onConsoleToggle: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final name = tester.renderObject<RenderParagraph>(
          find.text('WWWWWWWWWW'),
        );

        expect(tester.takeException(), isNull);
        expect(name.didExceedMaxLines, isTrue);
      },
    );
  });

  // The silent pedal never answers: a load ends after its 800-ms ACK timeout,
  // which pumpPastAckTimeout runs out.
  group('picking a preset from the rail', () {
    // The rail unmounts when the layout turns compact. A pick that ran on the
    // rail's own ref would throw on the load's first status write after the
    // flip and leave presetLoadingProvider stuck at true.
    testWidgets('a load started in the rail survives a flip to compact', (
      tester,
    ) async {
      final container = await pumpPage(
        tester,
        size: const Size(1280, 800),
        selectedEffects: const {},
      );

      await tester.tap(find.text('P02'));
      await tester.pump();

      expect(container.read(presetLoadingProvider), isTrue);

      tester.view.physicalSize = const Size(852, 393);
      await tester.pump();

      expect(find.byType(PresetRail), findsNothing);

      await pumpPastAckTimeout(tester);

      expect(tester.takeException(), isNull);
      expect(container.read(presetLoadingProvider), isFalse);
      expect(container.read(presetLoadStatusProvider), 'P02: no ACK (timeout)');
    });

    testWidgets('unsaved edits + Cancel keep the loaded preset', (
      tester,
    ) async {
      final container = await pumpPage(
        tester,
        size: const Size(1280, 800),
        overrides: [presetModifiedProvider.overrideWith((_) => true)],
      );

      await tester.tap(find.text('P02'));
      await tester.pumpAndSettle();

      expect(find.text('Discard unsaved changes?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(presetLoadingProvider), isFalse);
      expect(container.read(currentPresetProvider), const PresetRef(.user, 1));
      expect(container.read(presetLoadStatusProvider), isNull);
    });

    // A Patch Vol drag rebuilds the page on every step: the rail (50 rows)
    // must stay the identical widget, so Flutter skips rebuilding it.
    testWidgets('a page rebuild does not rebuild the rail', (tester) async {
      final container = await pumpPage(tester, size: const Size(1280, 800));
      final rail = tester.widget(find.byType(PresetRail));

      container.read(currentPresetStateProvider.notifier).state =
          loadedPresetState.copyWith(presetVolume: 45);
      await tester.pump();

      expect(find.text('45'), findsOneWidget);
      expect(tester.widget(find.byType(PresetRail)), same(rail));
    });
  });

  // setGlobalVolume reads its ref again after the send, and the rail
  // unmounts when the layout turns compact. A write running on the rail's
  // own ref would throw there and leave the old level showing.
  group('turning Master Vol in the rail', () {
    testWidgets('a level in flight survives a flip to compact', (tester) async {
      final transport = _PendingTransport();
      final container = await pumpPage(
        tester,
        size: const Size(1280, 800),
        overrides: [
          deviceServiceProvider.overrideWith((ref) {
            final service = DeviceService(transport)..startListening();

            ref.onDispose(service.dispose);

            return service;
          }),
        ],
      );

      final knob = find.descendant(
        of: find.byType(PresetRail),
        matching: find.byKey(const Key('knob')),
      );

      final mouse = TestPointer(1, .mouse);

      // One wheel tick up: 75 -> 76, sent and still in flight.
      await tester.sendEventToBinding(mouse.hover(tester.getCenter(knob)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -20)));
      await tester.pump();

      expect(transport.pending, hasLength(1));

      tester.view.physicalSize = const Size(852, 393);
      await tester.pump();
      await tester.pump();

      expect(find.byType(PresetRail), findsNothing);

      for (final send in transport.pending) {
        send.complete();
      }

      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(container.read(globalVolumeProvider), 76);
    });
  });
}
