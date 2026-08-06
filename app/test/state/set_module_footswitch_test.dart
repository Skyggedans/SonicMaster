import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport.dart';
import 'package:sonicmaster/model/decoded_preset_state.dart';
import 'package:sonicmaster/protocol/footswitch_frame.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';

class _NoopTransport implements Transport {
  @override
  Stream<Uint8List> rawPackets() => const Stream<Uint8List>.empty();
  @override
  Future<void> connect({String? target}) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Stream<bool>? connectionEvents() => null;
  @override
  Future<void> sendFrame(String frameHex) async {}
}

/// Captures every frame handed to [sendFrame].
class _SendSpy extends DeviceService {
  _SendSpy() : super(_NoopTransport());

  final List<String> sent = [];

  @override
  Future<void> sendFrame(String frameHex) async => sent.add(frameHex);
}

DecodedPresetState _state({int fs1 = 0, int fs2 = 0}) => DecodedPresetState(
  isCloneMode: false,
  presetVolume: 50,
  presetBpm: 120,
  moduleStates: const {},
  chainOrder: const [],
  footswitchFs1Mask: fs1,
  footswitchFs2Mask: fs2,
);

Future<WidgetRef> _pumpRef(
  WidgetTester tester,
  ProviderContainer container,
) async {
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

  return captured;
}

void main() {
  Future<(_SendSpy, ProviderContainer, WidgetRef)> setup(
    WidgetTester tester,
    DecodedPresetState initial,
  ) async {
    final service = _SendSpy();
    final container = ProviderContainer(
      overrides: [deviceServiceProvider.overrideWith((_) => service)],
    );

    addTearDown(container.dispose);
    final ref = await _pumpRef(tester, container);

    container.read(currentPresetStateProvider.notifier).state = initial;

    return (service, container, ref);
  }

  String on(int module, {required bool isFs2}) =>
      FootswitchFrame.build(moduleId: module, isFs2: isFs2, isOn: true);
  String off(int module, {required bool isFs2}) =>
      FootswitchFrame.build(moduleId: module, isFs2: isFs2, isOn: false);

  testWidgets('claiming FS2 (was broken) sends the FS2-ON write', (
    tester,
  ) async {
    final (service, container, ref) = await setup(tester, _state());

    await setModuleFootswitch(ref, 1, .fs2); // FX1 -> FS2, from None

    expect(service.sent, [on(1, isFs2: true)]);

    final st = container.read(currentPresetStateProvider)!;

    expect(st.footswitchFs2Mask, 1 << 1);
    expect(st.footswitchFs1Mask, 0);
    expect(container.read(presetModifiedProvider), isTrue);
  });

  testWidgets('switching FS2 -> FS1 turns FS1 on AND clears FS2', (
    tester,
  ) async {
    // DLY(7) currently on FS2.
    final (service, container, ref) = await setup(tester, _state(fs2: 1 << 7));

    await setModuleFootswitch(ref, 7, .fs1);

    expect(service.sent, [on(7, isFs2: false), off(7, isFs2: true)]);

    final st = container.read(currentPresetStateProvider)!;

    expect(st.footswitchFs1Mask, 1 << 7);
    expect(st.footswitchFs2Mask, 0);
  });

  testWidgets('None off FS2 sends the FS2-OFF write (was broken)', (
    tester,
  ) async {
    final (service, container, ref) = await setup(tester, _state(fs2: 1 << 7));

    await setModuleFootswitch(ref, 7, .none);

    expect(service.sent, [off(7, isFs2: true)]);
    expect(container.read(currentPresetStateProvider)!.footswitchFs2Mask, 0);
  });

  testWidgets('does NOT touch other modules', (tester) async {
    // NR(0) on FS1; DRV(2) claims FS2 — NR stays, no clear for DRV.
    final (service, container, ref) = await setup(tester, _state(fs1: 1 << 0));

    await setModuleFootswitch(ref, 2, .fs2);

    expect(service.sent, [on(2, isFs2: true)]);

    final st = container.read(currentPresetStateProvider)!;

    expect(st.footswitchFs1Mask, 1 << 0, reason: 'NR untouched');
    expect(st.footswitchFs2Mask, 1 << 2);
  });

  testWidgets('re-selecting the current assignment is a no-op', (tester) async {
    final (service, container, ref) = await setup(tester, _state(fs1: 1 << 1));

    await setModuleFootswitch(ref, 1, .fs1);

    expect(service.sent, isEmpty);
    expect(container.read(presetModifiedProvider), isFalse);
  });

  testWidgets('no-op while a load is in flight', (tester) async {
    final (service, container, ref) = await setup(tester, _state());

    container.read(presetLoadingProvider.notifier).state = true;
    await setModuleFootswitch(ref, 1, .fs1);

    expect(service.sent, isEmpty);
  });
}
