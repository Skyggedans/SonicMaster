import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/command_library.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/protocol/inbound_message.dart';
import 'package:sonicmaster/state/hardware_sync.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';

void main() {
  testWidgets('PresetSelected sets currentPreset/tab and clears modified', (
    tester,
  ) async {
    final container = ProviderContainer();

    addTearDown(container.dispose);
    late WidgetRef ref;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );
    // Pretend the current preset has unsaved edits, on the User tab.
    container.read(presetModifiedProvider.notifier).state = true;
    container.read(presetTabProvider.notifier).state = .user;

    // Real device preset-notify: index `hi*16+lo`. F01 = 03 02 = 50 (Factory).
    handleHardwareSync(
      ref,
      InboundMessage.classify(
        '8080F00902000100000006010204030302000000000000F7',
      ),
    );

    expect(
      container.read(currentPresetProvider),
      const PresetRef(PresetBank.factory, 1),
    );
    // Tab follows the pedal's bank so the rail can show/highlight it.
    expect(container.read(presetTabProvider), PresetBank.factory);
    expect(container.read(presetModifiedProvider), isFalse);
  });

  testWidgets('PresetSelected decodes User P01 from 00 00', (tester) async {
    final container = ProviderContainer();

    addTearDown(container.dispose);
    late WidgetRef ref;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );
    // U01 = hi/lo 00 00 = index 0 (the old (hi-3) formula dropped this).
    handleHardwareSync(
      ref,
      InboundMessage.classify(
        '8080F00107000100000006010204030000000000000000F7',
      ),
    );
    expect(
      container.read(currentPresetProvider),
      const PresetRef(PresetBank.user, 1),
    );
    expect(container.read(presetTabProvider), PresetBank.user);
  });

  testWidgets('PresetModifiedMessage marks modified and schedules a re-read', (
    tester,
  ) async {
    final container = ProviderContainer();

    addTearDown(container.dispose);
    late WidgetRef ref;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(container.read(presetModifiedProvider), isFalse);

    // The pedal's content-less "preset modified" notify (on-pedal edit).
    handleHardwareSync(
      ref,
      InboundMessage.classify('8080F0070A000100000003010204050001F7'),
    );
    // Marked modified immediately; the re-read is debounced.
    expect(container.read(presetModifiedProvider), isTrue);

    // Fire the debounced re-read (a no-op here: dataAssets isn't loaded) so the
    // timer doesn't leak into teardown.
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('a non-target frame leaves providers untouched', (tester) async {
    final container = ProviderContainer();

    addTearDown(container.dispose);
    late WidgetRef ref;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );
    // 010b notify -> classifyHardwareSync returns null -> no-op.
    handleHardwareSync(
      ref,
      InboundMessage.classify(
        '8080F00E020001000000060102010B0001000000000000F7',
      ),
    );
    expect(container.read(currentPresetProvider), isNull);
  });
}
