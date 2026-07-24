import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonicmaster/device/device_model.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/state/connection_prefs.dart';

void main() {
  Future<ConnectionPrefs> makePrefs([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);

    return ConnectionPrefs(await SharedPreferences.getInstance());
  }

  test('no stored intent -> no auto-connect profile', () async {
    final prefs = await makePrefs();

    expect(prefs.autoConnectProfile, isNull);
  });

  test('saveProfile(usb) arms auto-connect with no BLE name', () async {
    final prefs = await makePrefs();

    await prefs.saveProfile(.usb, null);
    final p = prefs.autoConnectProfile;

    expect(p, isNotNull);
    expect(p!.transport, TransportKind.usb);
    expect(p.bleName, isNull);
  });

  test('saveProfile(ble, name) arms auto-connect with the name', () async {
    final prefs = await makePrefs();

    await prefs.saveProfile(.ble, 'Smart Box BLE');
    final p = prefs.autoConnectProfile;

    expect(p!.transport, TransportKind.ble);
    expect(p.bleName, 'Smart Box BLE');
  });

  test(
    'saveProfile(usb) persists no ble_name, clearing any prior one',
    () async {
      final prefs = await makePrefs({'ble_name': 'Old BLE'});

      await prefs.saveProfile(.usb, 'stray');
      final raw = await SharedPreferences.getInstance();

      expect(raw.containsKey('ble_name'), isFalse);
      expect(prefs.autoConnectProfile!.bleName, isNull);
    },
  );

  test('clearAutoConnect disarms', () async {
    final prefs = await makePrefs();

    await prefs.saveProfile(.ble, 'Smart Box BLE');
    await prefs.clearAutoConnect();

    expect(prefs.autoConnectProfile, isNull);
  });

  test('clearAutoConnect keeps transport and ble_name for reference', () async {
    final prefs = await makePrefs();

    await prefs.saveProfile(.ble, 'Smart Box BLE');
    await prefs.clearAutoConnect();
    final raw = await SharedPreferences.getInstance();

    expect(raw.getBool('auto_connect'), isFalse);
    expect(raw.containsKey('transport'), isTrue);
    expect(raw.containsKey('ble_name'), isTrue);
  });

  test('BLE intent without a stored name is inert', () async {
    final prefs = await makePrefs({'auto_connect': true, 'transport': 'ble'});

    expect(prefs.autoConnectProfile, isNull);
  });

  test('auto_connect true but no transport key is inert', () async {
    final prefs = await makePrefs({'auto_connect': true});

    expect(prefs.autoConnectProfile, isNull);
  });

  test('connectionPrefsProvider throws until overridden', () {
    final c = ProviderContainer();

    addTearDown(c.dispose);
    expect(() => c.read(connectionPrefsProvider), throwsUnimplementedError);
  });

  test('modelOverride round-trips a stored model', () async {
    final prefs = await makePrefs();

    expect(prefs.modelOverride, isNull); // default = Auto

    await prefs.saveModelOverride(.pocketMaster);

    expect(prefs.modelOverride, DeviceModel.pocketMaster);

    await prefs.saveModelOverride(.smartBox);

    expect(prefs.modelOverride, DeviceModel.smartBox);
  });

  test('saveModelOverride(null / unknown) clears back to Auto', () async {
    final prefs = await makePrefs();

    await prefs.saveModelOverride(.smartBox);
    await prefs.saveModelOverride(null);

    expect(prefs.modelOverride, isNull);

    await prefs.saveModelOverride(.pocketMaster);
    await prefs.saveModelOverride(.unknown); // Auto sentinel

    expect(prefs.modelOverride, isNull);
  });
}
