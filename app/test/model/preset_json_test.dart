import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/model/decoded_preset_state.dart';
import 'package:sonicmaster/model/preset_json.dart';

void main() {
  late DataAssets data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await DataAssets.load();
  });

  test('presetToJson emits version/mode/volume and a module by name', () {
    const state = DecodedPresetState(
      isCloneMode: false,
      presetVolume: 75,
      presetBpm: 140,
      moduleStates: {'NR': true},
      chainOrder: ['NR'],
    );

    final json = presetToJson(
      state: state,
      selected: const {0: 1}, // NR -> Gate
      params: const {
        0: {0: 50},
      }, // THRE = 50
      data: data,
      presetName: 'P',
    );

    expect(json['version'], '1.0');
    expect(json['ampMode'], 'Normal');
    expect(json['presetVolume'], 75);
    expect(json['presetBpm'], 140);

    final nr = (json['modules'] as Map)['NR'] as Map;

    expect(nr['enabled'], true);
    expect(nr['effect'], 'Gate');
    expect(nr['parameters'], {'THRE': 50});
  });

  test('clone mode emits a "Clone" module (not AMP)', () {
    const state = DecodedPresetState(
      isCloneMode: true,
      presetVolume: 50,
      presetBpm: 120,
      moduleStates: {'AMP': true},
      chainOrder: [],
    );

    final json = presetToJson(
      state: state,
      selected: const {9: 901},
      params: const {},
      data: data,
    );

    final modules = json['modules'] as Map;

    expect(json['ampMode'], 'Clone');
    expect(modules.containsKey('Clone'), true);
    expect(modules.containsKey('AMP'), false);
    expect((modules['Clone'] as Map)['effect'], data.effects.byId(901)?.name);
  });

  test('importedPresetFromJson maps names to ids', () {
    final imp = importedPresetFromJson({
      'version': '1.0',
      'ampMode': 'Normal',
      'presetVolume': 75,
      'modules': {
        'NR': {
          'enabled': true,
          'effect': 'Gate',
          'parameters': {'THRE': 50},
        },
      },
      'signalChain': ['NR'],
    }, data);

    expect(imp.isCloneMode, false);
    expect(imp.presetVolume, 75);
    expect(imp.moduleStates[0], true);
    expect(imp.selectedEffects[0], 1); // Gate
    expect(imp.parameters[0]?[0], 50); // THRE
  });

  test('version mismatch throws', () {
    expect(
      () => importedPresetFromJson(const {'version': '2.0'}, data),
      throwsFormatException,
    );
  });

  test('unknown effect throws', () {
    expect(
      () => importedPresetFromJson(const {
        'version': '1.0',
        'modules': {
          'NR': {'enabled': true, 'effect': 'Nope', 'parameters': {}},
        },
        'signalChain': [],
      }, data),
      throwsFormatException,
    );
  });

  test('unknown module adds a warning and skips', () {
    final imp = importedPresetFromJson(const {
      'version': '1.0',
      'modules': {
        'BOGUS': {'enabled': true, 'effect': null, 'parameters': {}},
      },
      'signalChain': [],
    }, data);

    expect(imp.warnings.any((w) => w.contains('BOGUS')), true);
    expect(imp.moduleStates.isEmpty, true);
  });

  test('out-of-range param clamps to max with a warning', () {
    final imp = importedPresetFromJson(const {
      'version': '1.0',
      'modules': {
        'NR': {
          'enabled': true,
          'effect': 'Gate',
          'parameters': {'THRE': 9999},
        },
      },
      'signalChain': [],
    }, data);

    expect(imp.parameters[0]?[0], 100); // Gate THRE max
    expect(imp.warnings.any((w) => w.contains('clamped')), true);
  });

  test('presetVolume clamps to [0,100]', () {
    final imp = importedPresetFromJson(const {
      'version': '1.0',
      'presetVolume': 200,
      'modules': {},
      'signalChain': [],
    }, data);

    expect(imp.presetVolume, 100);
  });

  test('presetBpm clamps to [40,260]; absent -> default 120', () {
    final high = importedPresetFromJson(const {
      'version': '1.0',
      'presetBpm': 999,
      'modules': {},
      'signalChain': [],
    }, data);

    expect(high.presetBpm, 260);

    final absent = importedPresetFromJson(const {
      'version': '1.0',
      'modules': {},
      'signalChain': [],
    }, data);

    expect(absent.presetBpm, 120);
  });

  test('round-trips a module through export + import', () {
    const state = DecodedPresetState(
      isCloneMode: false,
      presetVolume: 60,
      presetBpm: 90,
      moduleStates: {'NR': true},
      chainOrder: ['NR'],
    );

    final json = presetToJson(
      state: state,
      selected: const {0: 1},
      params: const {
        0: {0: 42},
      },
      data: data,
    );

    final imp = importedPresetFromJson(json, data);

    expect(imp.selectedEffects[0], 1);
    expect(imp.parameters[0]?[0], 42);
    expect(imp.presetVolume, 60);
    expect(imp.presetBpm, 90);
  });
}
