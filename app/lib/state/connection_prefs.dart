import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device/device_model.dart';
import '../device/transport.dart';

/// The connection the app should restore on the next launch.
class ConnectionProfile {
  const ConnectionProfile({required this.transport, this.bleName});
  final TransportKind transport;
  final String? bleName; // null for USB (the port is a fixed default)
}

/// Persists the user's last connection intent across launches, backed by
/// [SharedPreferences]. The app auto-connects on startup iff [autoConnectProfile]
/// is non-null — armed by a successful connect ([saveProfile]), disarmed by a
/// manual disconnect ([clearAutoConnect]). An unexpected drop writes nothing, so
/// the profile stays armed.
class ConnectionPrefs {
  ConnectionPrefs(this._prefs);
  final SharedPreferences _prefs;

  static const _auto = 'auto_connect';
  static const _transport = 'transport';
  static const _bleName = 'ble_name';
  static const _modelOverride = 'device_model_override';

  /// The saved profile iff auto-connect is armed; else null. Returns null
  /// defensively for a BLE profile with no stored device name (never
  /// scan-guess), and for a missing/unrecognized transport key (a torn write
  /// must not be treated as armed).
  ConnectionProfile? get autoConnectProfile {
    if (_prefs.getBool(_auto) != true) return null;

    final t = _prefs.getString(_transport);

    if (t == 'ble') {
      final name = _prefs.getString(_bleName);

      if (name == null || name.isEmpty) return null;

      return ConnectionProfile(transport: .ble, bleName: name);
    }

    if (t == 'usb') {
      return const ConnectionProfile(transport: .usb);
    }

    return null; // missing/unknown transport -> treat as not armed
  }

  /// Record a successful connection and arm auto-connect. USB stores no name.
  Future<void> saveProfile(TransportKind transport, String? bleName) async {
    await _prefs.setBool(_auto, true);
    await _prefs.setString(_transport, transport == .ble ? 'ble' : 'usb');

    if (transport == .ble && bleName != null && bleName.isNotEmpty) {
      await _prefs.setString(_bleName, bleName);
    } else {
      await _prefs.remove(_bleName);
    }
  }

  /// Disarm auto-connect (keeps transport/name for reference).
  Future<void> clearAutoConnect() => _prefs.setBool(_auto, false);

  /// The persisted manual device-model override, or null for Auto (detect from
  /// the connection). [DeviceModel.unknown] is never stored — it is the Auto
  /// sentinel, cleared like null.
  DeviceModel? get modelOverride => switch (_prefs.getString(_modelOverride)) {
    'pocketMaster' => .pocketMaster,
    'smartBox' => .smartBox,
    _ => null,
  };

  /// Persist the manual override. Null or [DeviceModel.unknown] clears it (Auto).
  Future<void> saveModelOverride(DeviceModel? model) async {
    if (model == null || model == .unknown) {
      await _prefs.remove(_modelOverride);

      return;
    }

    await _prefs.setString(
      _modelOverride,
      model == .pocketMaster ? 'pocketMaster' : 'smartBox',
    );
  }
}

/// The app's [ConnectionPrefs]. Overridden in `main()` with a loaded
/// [SharedPreferences] instance so reads are synchronous everywhere.
final connectionPrefsProvider = Provider<ConnectionPrefs>(
  (_) => throw UnimplementedError(
    'connectionPrefsProvider must be overridden in the root ProviderScope',
  ),
);
