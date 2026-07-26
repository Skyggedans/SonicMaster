import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/device_model.dart';
import 'package:sonicmaster/model/command_library.dart';
import 'package:sonicmaster/model/device_capabilities.dart';

void main() {
  final caps = DeviceCapabilities.fromJson(
    jsonDecode(File('assets/data/device_capabilities.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  final commands = CommandLibrary.fromJson(
    jsonDecode(File('assets/data/command_library.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  const modules = [1, 2, 3, 4, 5, 6, 7, 8, 9];

  group('detect', () {
    test('USB port names map to models, case-insensitively', () {
      expect(
        caps.detect(name: 'Smart Box MIDI 1', kind: .usb),
        DeviceModel.smartBox,
      );
      expect(
        caps.detect(name: 'SONICAKE POCKET MASTER', kind: .usb),
        DeviceModel.pocketMaster,
      );
    });

    test('BLE advertised names map to models', () {
      expect(
        caps.detect(name: 'Smart Box BLE', kind: .ble),
        DeviceModel.smartBox,
      );
      expect(
        caps.detect(name: 'Pocket Master BLE', kind: .ble),
        DeviceModel.pocketMaster,
      );
    });

    test('a null or unrecognized name fails open to unknown', () {
      expect(caps.detect(name: null, kind: .usb), DeviceModel.unknown);
      expect(
        caps.detect(name: 'Some Other Pedal', kind: .ble),
        DeviceModel.unknown,
      );
    });
  });

  group('availableEffectIds', () {
    test('smartBox and unknown pass through the full pickable set', () {
      for (final moduleId in modules) {
        final all = commands.effectIdsFor(moduleId);

        expect(caps.availableEffectIds(commands, .smartBox, moduleId), all);
        expect(caps.availableEffectIds(commands, .unknown, moduleId), all);
      }
    });

    test('pocketMaster narrows the amp list to 301-322', () {
      final amps = caps.availableEffectIds(commands, .pocketMaster, 3);

      expect(amps, commands.effectIdsFor(3).where((id) => id <= 322).toList());
      expect(amps, isNot(contains(323)));
      expect(amps, isNot(contains(338)));
    });

    test('pocketMaster drops the Smart Box-only mods, delays, and cab', () {
      expect(
        caps.availableEffectIds(commands, .pocketMaster, 1),
        isNot(contains(120)), // Phaser ST (FX1)
      );
      expect(
        caps.availableEffectIds(commands, .pocketMaster, 6),
        isNot(contains(601)), // BBD Phaser (FX2)
      );
      expect(
        caps.availableEffectIds(commands, .pocketMaster, 7),
        isNot(contains(716)), // Echo (DLY)
      );
      expect(
        caps.availableEffectIds(commands, .pocketMaster, 4),
        isNot(contains(421)), // Bass 4x10 (IR)
      );
    });

    test('the pocketMaster manifest never drifts past the command library', () {
      for (final moduleId in modules) {
        final all = commands.effectIdsFor(moduleId).toSet();
        final pm = caps.availableEffectIds(commands, .pocketMaster, moduleId);

        expect(
          pm.every(all.contains),
          isTrue,
          reason: 'module $moduleId manifest id absent from command library',
        );

        final sorted = [...pm]..sort();

        expect(pm, sorted, reason: 'module $moduleId not sorted');
      }
    });
  });
}
