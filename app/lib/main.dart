import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'device/transport.dart';
import 'src/rust/frb_generated.dart';
import 'state/connection_prefs.dart';
import 'state/device_providers.dart';
import 'theme/app_colors.dart';
import 'ui/preset_browser_page.dart';

/// The desktop platforms that have a native window frame we replace with our
/// own frameless top bar.
bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Linux has no baked window-icon mechanism (Windows uses the .ico, macOS the
/// asset catalog), so set it from the bundled asset at runtime. Applies on X11;
/// on Wayland the taskbar icon comes from the .desktop app_id instead.
Future<void> _applyLinuxWindowIcon() async {
  if (!Platform.isLinux) return;

  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final iconPath = '$exeDir/data/flutter_assets/assets/images/app_icon.png';

  if (File(iconPath).existsSync()) {
    await windowManager.setIcon(iconPath);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await RustLib.init(); // native .nam→.clo generator bridge (clo_generator)

  if (_isDesktop) {
    await windowManager.ensureInitialized();

    const options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(960, 640),
      center: true,
      backgroundColor: Color(0x00000000),
      titleBarStyle: .hidden, // no native title bar; drag by our top bar
      windowButtonVisibility:
          false, // hide macOS traffic lights; we draw our own
      title: 'SonicMaster',
    );

    unawaited(
      windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.focus();
        await _applyLinuxWindowIcon();
      }),
    );
  }

  await initTransports(); // load both native plugin libs once

  final prefs = ConnectionPrefs(await SharedPreferences.getInstance());

  runApp(
    ProviderScope(
      overrides: [
        connectionPrefsProvider.overrideWithValue(prefs),
        // Seed the manual model override from the persisted value so a device
        // whose name we don't auto-recognize stays gated across launches.
        deviceModelOverrideProvider.overrideWith((_) => prefs.modelOverride),
      ],
      child: const SonicMasterApp(),
    ),
  );
}

class SonicMasterApp extends StatelessWidget {
  const SonicMasterApp({super.key});

  @override
  Widget build(BuildContext context) => WidgetsApp(
    title: 'SonicMaster',
    debugShowCheckedModeBanner: false,
    color: Palette.background,
    // Oswald is the app's display font everywhere; there is no Material theme.
    textStyle: const TextStyle(
      fontFamily: 'Oswald',
      color: Palette.textPrimary,
    ),
    pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
        PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
    home: const PresetBrowserPage(),
  );
}
