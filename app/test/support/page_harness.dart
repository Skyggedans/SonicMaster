import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/main.dart';
import 'package:sonicmaster/model/decoded_preset_state.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/state/connection_prefs.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/preset_browser_page.dart';

import 'fonts.dart';
import 'silent_transport.dart';
import 'test_assets.dart';

/// The decoded preset a connected page starts with: the full 9-module chain in
/// signal order (amp block contiguous), every module on.
const loadedPresetState = DecodedPresetState(
  isCloneMode: false,
  presetVolume: 44,
  presetBpm: 120,
  moduleStates: {
    'NR': true,
    'FX1': true,
    'DRV': true,
    'AMP': true,
    'IR': true,
    'EQ': true,
    'FX2': true,
    'DLY': true,
    'RVB': true,
  },
  chainOrder: ['NR', 'FX1', 'DRV', 'AMP', 'IR', 'EQ', 'FX2', 'DLY', 'RVB'],
);

/// The bundled data tables, read from disk once per test file.
final _assets = loadTestDataAssets();

/// Pumps the whole app ([SonicMasterApp]: its WidgetsApp, its frame and the
/// PresetBrowserPage home) at [size] logical px (dpr 1) over a fresh
/// [ProviderContainer], with Oswald loaded, and returns the container.
///
/// [isConnected] (the default) fakes a live pedal: 'Smart Box' over USB with
/// [current] loaded, named by [names] (default: P01 'Clean'), decoded as
/// [state], and the editor showing [selectedEffects] / [parameters] (default:
/// NR = Gate). false: no device ('No device connected').
///
/// [overrides] go after the harness's own, so they win (Riverpod keeps the
/// last override of a provider): pass e.g. presetModifiedProvider, or a
/// deviceServiceProvider over your own [SilentTransport] to inspect its
/// frames. The harness never overrides mobileScreenProvider.
///
/// [home] replaces the app's first route: pass the page wrapped in whatever
/// the test needs around it (e.g. an ambient text style).
///
/// Fake-time rules for whole-page tests:
/// * The pedal never answers. A test that starts a preset load (or any other
///   ACK wait) must call [pumpPastAckTimeout] before it ends.
/// * While connected the page runs a 2-s heartbeat (PresetBrowserPage) that
///   starts device I/O with timers of its own: never advance 2 s or more of
///   fake time in a connected test (pumpAndSettle included).
Future<ProviderContainer> pumpPage(
  WidgetTester tester, {
  required Size size,
  bool isConnected = true,
  PresetRef current = const PresetRef(.user, 1),
  Map<PresetRef, String>? names,
  DecodedPresetState state = loadedPresetState,
  Map<int, int> selectedEffects = const {0: 1},
  Map<int, Map<int, num>> parameters = const {
    0: {0: 50},
  },
  List<Override> overrides = const [],
  Widget home = const PresetBrowserPage(),
}) async {
  await loadOswald();
  SharedPreferences.setMockInitialValues({});
  // A fixed version: the rail footer shows it, so the page goldens never
  // change with a version bump.
  PackageInfo.setMockInitialValues(
    appName: 'SonicMaster',
    packageName: 'dev.skyggedans.sonicmaster',
    version: '1.0.8',
    buildNumber: '1',
    buildSignature: '',
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final prefs = ConnectionPrefs(await SharedPreferences.getInstance());
  final container = ProviderContainer(
    overrides: [
      connectionPrefsProvider.overrideWithValue(prefs),
      deviceServiceProvider.overrideWith((ref) {
        final service = DeviceService(SilentTransport())..startListening();

        ref.onDispose(service.dispose);

        return service;
      }),
      dataAssetsProvider.overrideWith((_) => _assets),
      if (isConnected) ...[
        connectionStateProvider.overrideWith((_) => true),
        connectedDeviceNameProvider.overrideWith((_) => 'Smart Box'),
        currentPresetProvider.overrideWith((_) => current),
        presetNamesProvider.overrideWith(
          (_) => names ?? {const PresetRef(.user, 1): 'Clean'},
        ),
        currentPresetStateProvider.overrideWith((_) => state),
        currentSelectedEffectsProvider.overrideWith((_) => selectedEffects),
        currentParametersProvider.overrideWith((_) => parameters),
      ],
      ...overrides,
    ],
  );

  addTearDown(container.dispose);
  await container.read(dataAssetsProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: SonicMasterApp(home: home),
    ),
  );
  // The page's post-frame knob-row measurement lands in the second frame.
  await tester.pump();

  return container;
}
