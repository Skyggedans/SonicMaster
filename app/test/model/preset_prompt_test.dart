import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/device_model.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/model/preset_json.dart';
import 'package:sonicmaster/model/preset_prompt.dart';

void main() {
  late DataAssets data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await DataAssets.load();
  });

  test('the template imports cleanly, with no warnings', () {
    for (final model in [DeviceModel.pocketMaster, DeviceModel.smartBox]) {
      final imported = importedPresetFromJson(
        presetTemplate(data, model),
        data,
      );

      expect(imported.warnings, isEmpty, reason: '$model');
      expect(imported.selectedEffects.length, 9, reason: '$model');
    }
  });

  test('the catalog lists only the effects the model supports', () {
    final pm = effectCatalog(data, DeviceModel.pocketMaster);
    final sb = effectCatalog(data, DeviceModel.smartBox);

    expect(pm, contains('## NR'));
    expect(pm, contains('"Gate"'));
    expect(sb.length, greaterThan(pm.length));
  });

  test('the system prompt embeds the template and the catalog', () {
    final prompt = buildPresetSystemPrompt(data, DeviceModel.pocketMaster);

    expect(prompt, contains('"signalChain"'));
    expect(prompt, contains('## RVB'));
  });
}
