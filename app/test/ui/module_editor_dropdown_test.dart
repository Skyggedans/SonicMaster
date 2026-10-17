import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/device_model.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/module_editor.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

import '../support/test_assets.dart';

void main() {
  final assets = loadTestDataAssets();

  // Renders the AMP (module 3) editor for [model] and returns the effect-type
  // dropdown's offered ids. The effect-type dropdown is built before any
  // parameter-select dropdown, so `.first` reliably targets it.
  Future<List<int>> ampDropdownIds(
    WidgetTester tester,
    DeviceModel model,
  ) async {
    final container = ProviderContainer(
      overrides: [
        dataAssetsProvider.overrideWith((_) => assets),
        effectiveDeviceModelProvider.overrideWithValue(model),
        currentSelectedEffectsProvider.overrideWith((_) => {3: 301}),
      ],
    );

    addTearDown(container.dispose);
    await container.read(dataAssetsProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Directionality(
          textDirection: .ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 480,
                child: SingleChildScrollView(child: ModuleEditor(3)),
              ),
            ),
          ),
        ),
      ),
    );

    final dropdown = tester.widget<SonicDropdown<int>>(
      find.byType(SonicDropdown<int>).first,
    );

    return dropdown.items.map((item) => item.value).toList();
  }

  testWidgets('AMP dropdown offers every amp for Smart Box', (tester) async {
    final ids = await ampDropdownIds(tester, .smartBox);

    expect(ids, assets.commands.effectIdsFor(3));
    expect(ids, contains(338)); // Doctor OD — a Smart Box-only amp
  });

  testWidgets('AMP dropdown hides Smart Box-only amps for Pocket Master', (
    tester,
  ) async {
    final ids = await ampDropdownIds(tester, .pocketMaster);

    expect(
      ids,
      assets.commands.effectIdsFor(3).where((id) => id <= 322).toList(),
    );
    expect(ids, isNot(contains(323)));
    expect(ids, isNot(contains(338)));
    expect(ids, contains(301));
    expect(ids, contains(322));
  });
}
