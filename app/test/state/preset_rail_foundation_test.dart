import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/command_library.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/state/reconnect.dart';

void main() {
  test(
    'presetChipLabel uses a colon separator, or bare label when unnamed',
    () {
      const u6 = PresetRef(.user, 6);

      expect(presetChipLabel(u6, const {}), 'P06');
      expect(presetChipLabel(u6, {u6: 'Solo Boost'}), 'P06: Solo Boost');
    },
  );

  test('presetTabProvider defaults to User', () {
    final c = ProviderContainer();

    addTearDown(c.dispose);
    expect(c.read(presetTabProvider), PresetBank.user);
  });

  testWidgets('applyUserDisconnect clears BLE target and marks disconnected', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        connectionStateProvider.overrideWith((_) => true),
        lastBleTargetProvider.overrideWith((_) => 'Smart Box BLE'),
      ],
    );

    addTearDown(container.dispose);
    late WidgetRef captured;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    applyUserDisconnect(captured);

    expect(container.read(connectionStateProvider), false);
    expect(container.read(lastBleTargetProvider), isNull);
    expect(container.read(presetLoadStatusProvider), 'disconnected');
  });
}
