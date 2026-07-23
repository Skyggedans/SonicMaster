import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_service.dart';
import '../model/chain_order.dart';
import '../model/data_assets.dart';
import '../model/decoded_preset_state.dart';
import '../model/footswitch_assignment.dart';
import '../model/footswitch_state.dart';
import '../model/global_settings.dart';
import '../model/preset_ref.dart';
import '../protocol/footswitch_frame.dart';
import '../protocol/global_settings_decoder.dart';
import '../protocol/name_dump_decoder.dart';
import '../protocol/param_value_key.dart';
import '../protocol/parameter_values_decoder.dart';
import '../protocol/preset_field_frame.dart';
import '../protocol/preset_name_codec.dart';
import '../protocol/preset_state_decoder.dart';
import '../protocol/save_preset_frame.dart';
import '../protocol/selected_effects_decoder.dart';
import 'data_providers.dart';
import 'device_providers.dart';
import 'edit_providers.dart'; // selectedModuleProvider (reset by setAmpMode)
import 'names_providers.dart';

/// The last preset successfully loaded onto the device.
final currentPresetProvider = StateProvider<PresetRef?>((ref) => null);

/// The decoded state (modules/order/volume) of the current preset, if fetched.
final currentPresetStateProvider = StateProvider<DecodedPresetState?>(
  (ref) => null,
);

/// The selected effect fxId per module of the current preset (moduleId -> fxId).
final currentSelectedEffectsProvider = StateProvider<Map<int, int>>(
  (ref) => const {},
);

/// Decoded parameter values of the current preset: moduleId -> algId -> value.
final currentParametersProvider = StateProvider<Map<int, Map<int, num>>>(
  (ref) => const {},
);

/// Human-readable result of the last load attempt (for the UI).
final presetLoadStatusProvider = StateProvider<String?>((ref) => null);

/// Clone-import upload progress as a 0..1 fraction for the progress modal; null
/// during the (indeterminate) NAM-conversion phase.
final cloneImportProgressProvider = StateProvider<double?>((ref) => null);

/// True while a preset load is in flight — used to serialize loads (the wire
/// ACK carries no correlation id, so overlapping loads could cross-complete).
final presetLoadingProvider = StateProvider<bool>((ref) => false);

/// True once the current preset has unsaved edits (the `*` marker).
final presetModifiedProvider = StateProvider<bool>((ref) => false);

/// Loads [preset] onto the device: send its `0403` frame, await the ACK.
/// Called from the UI, so it takes a [WidgetRef]. Ignores taps while a load is
/// already in flight.
Future<void> loadPreset(WidgetRef ref, PresetRef preset) async {
  if (ref.read(presetLoadingProvider)) return;

  void status(String s) =>
      ref.read(presetLoadStatusProvider.notifier).state = s;

  final dataAsync = ref.read(dataAssetsProvider);
  final data = dataAsync.valueOrNull;

  if (data == null) {
    status(dataAsync.hasError ? 'data load failed' : 'data still loading…');

    return;
  }

  final frame = data.commands.presetSelect(preset.bank, preset.number);

  if (frame == null) {
    status('no command for ${preset.label}');

    return;
  }

  ref.read(presetLoadingProvider.notifier).state = true;

  try {
    final service = ref.read(deviceServiceProvider);
    final ok = await service.sendAndAwaitAck(frame);

    if (ok) {
      ref.read(currentPresetProvider.notifier).state = preset;
      ref.read(presetModifiedProvider.notifier).state = false;
      status('loaded ${preset.label}');
      await refreshDecodedState(ref); // fetch + decode the preset's content
    } else {
      status('${preset.label}: no ACK (timeout)');
    }
  } catch (e) {
    status('${preset.label}: send failed — $e');
  } finally {
    ref.read(presetLoadingProvider.notifier).state = false;
  }
}

/// Re-reads the current preset state from the device and refreshes the decoded
/// providers (state / selected effects / params). Best-effort; clears on failure.
Future<void> refreshDecodedState(WidgetRef ref) async {
  final data = ref.read(dataAssetsProvider).valueOrNull;

  if (data == null) return;

  final service = ref.read(deviceServiceProvider);

  void clear() {
    ref.read(currentPresetStateProvider.notifier).state = null;
    ref.read(currentSelectedEffectsProvider.notifier).state = const {};
    ref.read(currentParametersProvider.notifier).state = const {};
  }

  try {
    // The reassembled state dump can lag under connect-time contention (it
    // queues behind the ~50-packet name dump), so a single 1s window often
    // times out spuriously and clears the editor to "no decoded effect".
    // Retry a few times with a wider window before giving up.
    String? dumpHex;

    for (var attempt = 0; attempt < 3 && dumpHex == null; attempt++) {
      dumpHex = await service.requestStateDump(
        timeout: const Duration(seconds: 3),
      );
    }

    if (dumpHex == null) {
      clear();

      return;
    }

    applyDecodedDump(ref, data, dumpHex);
  } catch (_) {
    clear();
  }
}

/// Decodes a preset-state dump [dumpHex] and stores it into the decoded-state
/// providers. Shared by [refreshDecodedState] (solicited) and the hardware-sync
/// handler (unsolicited device broadcast).
void applyDecodedDump(WidgetRef ref, DataAssets data, String dumpHex) {
  final selected = SelectedEffectsDecoder(data.signatures).decode(dumpHex);

  ref.read(currentPresetStateProvider.notifier).state = PresetStateDecoder(
    data.modules,
  ).decode(dumpHex);
  ref.read(currentSelectedEffectsProvider.notifier).state = selected;
  ref.read(currentParametersProvider.notifier).state = ParameterValuesDecoder(
    data.parameters,
  ).decode(dumpHex, selected, data.effects);
}

/// Fetches the pedal's stored preset + User-Profile + User-IR names in the
/// background and populates [presetNamesProvider] / [userNamesProvider].
/// Best-effort: any request that times out or throws is skipped without
/// disturbing the others or the connect flow. Serialized against other device
/// reads by the service's IO gate, so it is safe to fire unawaited right after
/// connect. Not a preset edit — never sets [presetModifiedProvider].
Future<void> refreshNames(WidgetRef ref) async {
  // Wait for the data tables (the character map) to load: on startup
  // auto-connect this can run before DataAssets.load() resolves, and reading
  // `valueOrNull` too early would skip the entire names fetch (never retried,
  // so names would stay blank until a manual reconnect). Fired unawaited from
  // connectAndSync, so awaiting the load here is safe.
  final DataAssets data;

  try {
    data = await ref.read(dataAssetsProvider.future);
  } catch (_) {
    return; // assets failed to load — nothing to decode against
  }

  final service = ref.read(deviceServiceProvider);
  final chars = data.characters;

  // The preset-names dump is large (~50 USB packets); a single 2s read can time
  // out under connect-time contention, leaving names blank. Retry a few times
  // with a longer timeout. Only replace on a non-empty decode so a flaky fetch
  // can't wipe already-good names; best-effort, so a persistent failure is
  // harmless.
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final dump = await service.requestPresetNames(
        timeout: const Duration(seconds: 4),
      );

      if (dump != null) {
        final decoded = decodePresetNames(dump, chars);

        if (decoded.isNotEmpty) {
          ref.read(presetNamesProvider.notifier).state = decoded;
          break;
        }
      }
    } catch (_) {
      // best-effort; try again
    }
  }

  final userNames = {...ref.read(userNamesProvider)};

  try {
    final dump = await service.requestUserNames(
      DeviceService.cloneNamesRequest,
    );

    if (dump != null) {
      final names = decodeUserNames(
        dump,
        chars,
        fallbackPrefix: 'User Profile',
      );

      for (final (i, name) in names.indexed) {
        userNames[901 + i] = name;
      }
    }
  } catch (_) {
    // best-effort
  }

  try {
    final dump = await service.requestUserNames(DeviceService.irNamesRequest);

    if (dump != null) {
      final names = decodeUserNames(dump, chars, fallbackPrefix: 'User IR');

      for (final (i, name) in names.indexed) {
        userNames[416 + i] = name;
      }
    }
  } catch (_) {
    // best-effort
  }

  ref.read(userNamesProvider.notifier).state = userNames;
}

/// Re-reads just the User-IR slot names (416–420) and updates
/// [userNamesProvider]. Faster than [refreshNames] after an IR upload/rename/
/// clear — it skips the large preset-names dump. Best-effort.
Future<void> refreshIrNames(WidgetRef ref) async {
  final DataAssets data;

  try {
    data = await ref.read(dataAssetsProvider.future);
  } catch (_) {
    return;
  }

  try {
    final dump = await ref
        .read(deviceServiceProvider)
        .requestUserNames(DeviceService.irNamesRequest);

    if (dump == null) return;

    final names = decodeUserNames(
      dump,
      data.characters,
      fallbackPrefix: 'User IR',
    );

    final userNames = {...ref.read(userNamesProvider)};

    for (final (i, name) in names.indexed) {
      userNames[416 + i] = name;
    }

    ref.read(userNamesProvider.notifier).state = userNames;
  } catch (_) {
    // best-effort
  }
}

/// Re-reads just the User-Profile / clone slot names (901–905) and updates
/// [userNamesProvider]. The clone analogue of [refreshIrNames] — used before/
/// after a clone upload (`020204`). Best-effort.
Future<void> refreshCloneNames(WidgetRef ref) async {
  final DataAssets data;

  try {
    data = await ref.read(dataAssetsProvider.future);
  } catch (_) {
    return;
  }

  try {
    final dump = await ref
        .read(deviceServiceProvider)
        .requestUserNames(DeviceService.cloneNamesRequest);

    if (dump == null) return;

    final names = decodeUserNames(
      dump,
      data.characters,
      fallbackPrefix: 'User Profile',
    );

    final userNames = {...ref.read(userNamesProvider)};

    for (final (i, name) in names.indexed) {
      userNames[901 + i] = name;
    }

    ref.read(userNamesProvider.notifier).state = userNames;
  } catch (_) {
    // best-effort
  }
}

/// Changes [moduleId]'s effect to [effectId] (`0407`), then re-reads state
/// (the new effect has different params).
Future<void> setEffectType(WidgetRef ref, int moduleId, int effectId) async {
  if (ref.read(presetLoadingProvider)) return; // don't edit mid-load

  final data = ref.read(dataAssetsProvider).valueOrNull;

  if (data == null) return;

  final frame = data.commands.effectType(moduleId, effectId);

  if (frame == null) return;

  try {
    await ref.read(deviceServiceProvider).sendFrame(frame);
  } catch (e) {
    ref.read(presetLoadStatusProvider.notifier).state = 'edit failed: $e';

    return;
  }

  ref.read(presetModifiedProvider.notifier).state = true;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await refreshDecodedState(ref);
}

/// Turns [moduleId] on/off (`0409`), optimistically updating the module state.
Future<void> toggleModule(WidgetRef ref, int moduleId, bool isOn) async {
  if (ref.read(presetLoadingProvider)) return; // don't edit mid-load

  final data = ref.read(dataAssetsProvider).valueOrNull;

  if (data == null) return;

  final frame = isOn
      ? data.commands.moduleOn(moduleId)
      : data.commands.moduleOff(moduleId);

  if (frame == null) return;

  try {
    await ref.read(deviceServiceProvider).sendFrame(frame);
  } catch (e) {
    ref.read(presetLoadStatusProvider.notifier).state = 'edit failed: $e';

    return;
  }

  final st = ref.read(currentPresetStateProvider);
  final name = data.modules.nameOf(moduleId);

  if (st != null && name != null) {
    ref.read(currentPresetStateProvider.notifier).state = st.copyWith(
      moduleStates: {...st.moduleStates, name: isOn},
    );
  }

  ref.read(presetModifiedProvider.notifier).state = true;
}

/// Reorders the signal chain (`0404`) to [newGroups] (collapsed 6-group form,
/// e.g. from a drag), optimistically updating `chainOrder`. No-op mid-load.
Future<void> reorderChain(WidgetRef ref, List<List<String>> newGroups) async {
  if (ref.read(presetLoadingProvider)) return; // don't edit mid-load

  final data = ref.read(dataAssetsProvider).valueOrNull;

  if (data == null) return;

  final order = flattenChain(newGroups);
  final frame = data.commands.chainOrderCommand(chainKey(newGroups));

  if (frame == null) {
    ref.read(presetLoadStatusProvider.notifier).state = 'reorder unavailable';

    return;
  }

  // Apply the optimistic order BEFORE sending: reorder replaces the whole
  // chainOrder, and the next drag derives its groups from this state, so a
  // rapid follow-up drag must build on the new order, not a stale one. On a
  // send failure the shown order self-heals on the next preset (re)load.
  final st = ref.read(currentPresetStateProvider);

  if (st != null) {
    ref.read(currentPresetStateProvider.notifier).state = st.copyWith(
      chainOrder: order,
    );
  }

  ref.read(presetModifiedProvider.notifier).state = true;

  try {
    await ref.read(deviceServiceProvider).sendFrame(frame);
  } catch (e) {
    ref.read(presetLoadStatusProvider.notifier).state = 'edit failed: $e';
  }
}

/// Sets [moduleId]/[algId] to [value] on the device (`0408`). Optimistically
/// updates the decoded-params provider and marks the preset modified. Does
/// nothing if the value has no command in the table.
Future<void> setParameter(
  WidgetRef ref,
  int moduleId,
  int algId,
  num value,
) async {
  if (ref.read(presetLoadingProvider)) return; // don't edit mid-load

  final data = ref.read(dataAssetsProvider).valueOrNull;

  if (data == null) return;

  final frame = data.commands.parameterCommand(
    moduleId,
    algId,
    formatParamValueKey(value),
  );

  if (frame == null) return; // value not in the command table

  try {
    await ref.read(deviceServiceProvider).sendFrame(frame);
  } catch (e) {
    ref.read(presetLoadStatusProvider.notifier).state = 'edit failed: $e';

    return;
  }

  final params = {...ref.read(currentParametersProvider)};

  params[moduleId] = {...?params[moduleId], algId: value};
  ref.read(currentParametersProvider.notifier).state = params;
  ref.read(presetModifiedProvider.notifier).state = true;
}

/// Saves the current live edits to User slot [slot] (1–50) with [name]
/// (`040A`, flash write). Returns true on ACK; clears the modified marker and
/// makes the saved slot current. When saving to a *different* slot than the one
/// loaded (a "Save As"), also re-selects it on the device so the pedal's active
/// preset and the app agree. No-op mid-load or for an out-of-range slot.
/// Brackets its device I/O with [presetLoadingProvider] so it serializes
/// against loads/edits (the wire ACK carries no correlation id).
Future<bool> savePreset(WidgetRef ref, int slot, String name) async {
  if (ref.read(presetLoadingProvider)) return false; // don't save mid-load

  final data = ref.read(dataAssetsProvider).valueOrNull;

  if (data == null) return false;

  if (slot < 1 || slot > 50) return false;

  final status = ref.read(presetLoadStatusProvider.notifier);
  final frame = SavePresetFrame(
    PresetNameCodec(data.characters),
  ).build(name: name, presetNumber: slot);

  final cur = ref.read(currentPresetProvider);
  final sameSlot = cur != null && cur.bank == .user && cur.number == slot;

  ref.read(presetLoadingProvider.notifier).state = true;

  try {
    final ok = await ref.read(deviceServiceProvider).sendAndAwaitAck(frame);

    if (!ok) {
      status.state = 'save: no ACK (timeout)';

      return false;
    }

    // A cross-slot "Save As" leaves the device on the originally-loaded preset;
    // re-select the target so the pedal and the decoded view reflect it. A
    // same-slot save needs no reload — the live state already matches.
    if (!sameSlot) {
      final selectFrame = data.commands.presetSelect(.user, slot);

      if (selectFrame != null) {
        // Let the flash write commit before re-selecting, or the reload could
        // read the slot's pre-save content (same settle the save probe needed).
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await ref.read(deviceServiceProvider).sendAndAwaitAck(selectFrame);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await refreshDecodedState(ref);
      }
    }

    final saved = PresetRef(.user, slot);

    ref.read(currentPresetProvider.notifier).state = saved;
    ref.read(presetNamesProvider.notifier).state = {
      ...ref.read(presetNamesProvider),
      saved: name,
    };
    ref.read(presetModifiedProvider.notifier).state = false;
    status.state = 'saved "$name" to U${slot.toString().padLeft(2, '0')}';

    return true;
  } catch (e) {
    status.state = 'save failed: $e';

    return false;
  } finally {
    ref.read(presetLoadingProvider.notifier).state = false;
  }
}

/// Device-global master volume (0–100). Starts at the pedal's default (75) and
/// is synced to the real device value by [refreshGlobalSettings] (on connect /
/// when the settings dialog opens); user edits via [setGlobalVolume].
final globalVolumeProvider = StateProvider<int>((ref) => 75);

/// Sets the current preset's volume (`0402`, 0–100), optimistically updating the
/// decoded state and marking the preset modified. No-op mid-load.
Future<void> setPresetVolume(WidgetRef ref, int value) async {
  if (ref.read(presetLoadingProvider)) return; // don't edit mid-load

  final data = ref.read(dataAssetsProvider).valueOrNull;

  if (data == null) return;

  final frame = data.commands.globalCommand('presetVolume', value);

  if (frame == null) return;

  try {
    await ref.read(deviceServiceProvider).sendFrame(frame);
  } catch (e) {
    ref.read(presetLoadStatusProvider.notifier).state = 'edit failed: $e';

    return;
  }

  final st = ref.read(currentPresetStateProvider);

  if (st != null) {
    ref.read(currentPresetStateProvider.notifier).state = st.copyWith(
      presetVolume: value,
    );
  }

  ref.read(presetModifiedProvider.notifier).state = true;
}

/// Preset BPM range exposed by the official app; the tempo every Sync-capable
/// effect follows. There is no global tempo — this lives on the preset.
const presetBpmMin = 40;
const presetBpmMax = 260;

/// Sets the current preset's BPM, optimistically updating the decoded state and
/// marking the preset modified. Unlike volume, BPM has no captured command —
/// the frame is synthesized (`0402` field 2, 16-bit LE). No-op mid-load.
Future<void> setPresetBpm(WidgetRef ref, int value) async {
  if (ref.read(presetLoadingProvider)) return; // don't edit mid-load

  final bpm = value.clamp(presetBpmMin, presetBpmMax);
  final frame = PresetFieldFrame.build(
    field: PresetFieldFrame.bpmField,
    value: bpm,
  );

  try {
    await ref.read(deviceServiceProvider).sendFrame(frame);
  } catch (e) {
    ref.read(presetLoadStatusProvider.notifier).state = 'edit failed: $e';

    return;
  }

  final st = ref.read(currentPresetStateProvider);

  if (st != null) {
    ref.read(currentPresetStateProvider.notifier).state = st.copyWith(
      presetBpm: bpm,
    );
  }

  ref.read(presetModifiedProvider.notifier).state = true;
}

/// Assigns [moduleId] to footswitch [assignment] (register `0x4D`, `11 4D`),
/// optimistically updating the decoded state and marking the preset modified.
/// Each `0x4D` write toggles ONE switch, so a radio None/FS1/FS2 change sends up
/// to two: turn the target switch on, then turn off whichever other switch this
/// module was on. A re-tap of the current assignment is a no-op. No-op mid-load.
Future<void> setModuleFootswitch(
  WidgetRef ref,
  int moduleId,
  FootswitchAssignment assignment,
) async {
  if (ref.read(presetLoadingProvider)) return; // don't edit mid-load

  final bit = 1 << moduleId;

  // Skip a redundant re-tap: the segmented control fires onChanged even for the
  // already-active segment, and sending would needlessly flag the preset dirty.
  final decoded = ref.read(currentPresetStateProvider);
  final wasOnFs1 = ((decoded?.footswitchFs1Mask ?? 0) & bit) != 0;
  final wasOnFs2 = ((decoded?.footswitchFs2Mask ?? 0) & bit) != 0;
  final current = footswitchAssignmentOf(
    decoded?.footswitchFs1Mask ?? 0,
    decoded?.footswitchFs2Mask ?? 0,
    moduleId,
  );

  if (assignment == current) return;

  // Turn the chosen switch on, then clear whichever other switch was set.
  final frames = <String>[
    if (assignment == .fs1)
      FootswitchFrame.build(moduleId: moduleId, isFs2: false, isOn: true),
    if (assignment == .fs2)
      FootswitchFrame.build(moduleId: moduleId, isFs2: true, isOn: true),
    if (assignment != .fs1 && wasOnFs1)
      FootswitchFrame.build(moduleId: moduleId, isFs2: false, isOn: false),
    if (assignment != .fs2 && wasOnFs2)
      FootswitchFrame.build(moduleId: moduleId, isFs2: true, isOn: false),
  ];

  try {
    for (final frame in frames) {
      await ref.read(deviceServiceProvider).sendFrame(frame);
    }
  } catch (e) {
    ref.read(presetLoadStatusProvider.notifier).state = 'edit failed: $e';

    return;
  }

  final st = ref.read(currentPresetStateProvider);

  if (st != null) {
    final fs1 = assignment == .fs1
        ? st.footswitchFs1Mask | bit
        : st.footswitchFs1Mask & ~bit;

    final fs2 = assignment == .fs2
        ? st.footswitchFs2Mask | bit
        : st.footswitchFs2Mask & ~bit;

    ref.read(currentPresetStateProvider.notifier).state = st
        .withFootswitchMasks(fs1Mask: fs1, fs2Mask: fs2);
  }

  ref.read(presetModifiedProvider.notifier).state = true;
}

/// Sets the device-global master volume (`0101`, 0–100), optimistically updating
/// [globalVolumeProvider]. Not a preset edit — does not mark the preset
/// modified. No-op mid-load.
Future<void> setGlobalVolume(WidgetRef ref, int value) async {
  if (ref.read(presetLoadingProvider)) return; // don't edit mid-load

  ref.read(_globalEditAtProvider.notifier).state = DateTime.now();
  final data = ref.read(dataAssetsProvider).valueOrNull;

  if (data == null) return;

  final frame = data.commands.globalCommand('globalVolume', value);

  if (frame == null) return;

  try {
    await ref.read(deviceServiceProvider).sendFrame(frame);
  } catch (e) {
    ref.read(presetLoadStatusProvider.notifier).state = 'edit failed: $e';

    return;
  }

  ref.read(globalVolumeProvider.notifier).state = value;
  // Keep the decoded-settings snapshot coherent with the master slider.
  final g = ref.read(globalSettingsProvider);

  if (g != null) {
    ref.read(globalSettingsProvider.notifier).state = g.copyWith(
      globalVolume: value,
    );
  }
}

/// The pedal's device-global settings, once read. Null until first fetched.
final globalSettingsProvider = StateProvider<GlobalSettings?>((ref) => null);

/// When the user last edited a global control (Master / levels). The background
/// poll skips for a moment after so it can't clobber an in-progress knob drag.
final _globalEditAtProvider = StateProvider<DateTime?>((_) => null);

/// Reads + decodes the device-global settings into [globalSettingsProvider] and
/// syncs [globalVolumeProvider] so the master slider reflects the real value.
/// Best-effort; leaves providers unchanged on a missing/malformed dump. Holds
/// [presetLoadingProvider] for the duration so the level sliders are disabled
/// (a mid-read edit can't be clobbered by the read's result) and a preset load
/// can't run a state-dump request against the same inbound stream concurrently.
Future<void> refreshGlobalSettings(WidgetRef ref) async {
  if (ref.read(presetLoadingProvider)) return; // don't read mid-load

  final service = ref.read(deviceServiceProvider);

  ref.read(presetLoadingProvider.notifier).state = true;

  try {
    final dump = await service.requestGlobalSettings();

    if (dump == null) return;

    final g = const GlobalSettingsDecoder().decode(dump);

    if (g == null) return;

    ref.read(globalSettingsProvider.notifier).state = g;
    ref.read(globalVolumeProvider.notifier).state = g.globalVolume;
  } catch (_) {
    // best-effort
  } finally {
    ref.read(presetLoadingProvider.notifier).state = false;
  }
}

/// Guards [pollGlobalSettings] against self-overlap: a stalled poll must not let
/// the next 2s tick stack another request on the serialized IO gate.
bool _pollInFlight = false;

/// Background poll that keeps the Master knob (and dialog levels) in sync with
/// on-pedal changes — the pedal never pushes global-settings edits. Unlike
/// [refreshGlobalSettings] this does NOT hold [presetLoadingProvider] (so it
/// never disables knobs or blocks edits) and it skips while the user is editing
/// a global control, so it can't clobber an in-progress knob drag. Best-effort;
/// silent on any timeout/decode failure.
Future<void> pollGlobalSettings(WidgetRef ref) async {
  bool isEditingRecently() {
    final t = ref.read(_globalEditAtProvider);

    return t != null &&
        DateTime.now().difference(t) < const Duration(milliseconds: 1500);
  }

  if (_pollInFlight || ref.read(presetLoadingProvider) || isEditingRecently()) {
    return;
  }

  _pollInFlight = true;

  try {
    String? dump;

    try {
      dump = await ref.read(deviceServiceProvider).requestGlobalSettings();
    } catch (_) {
      return;
    }

    if (dump == null) return;

    final g = const GlobalSettingsDecoder().decode(dump);

    if (g == null) return;

    // Re-check after the async gap — a drag or load may have started meanwhile.
    if (ref.read(presetLoadingProvider) || isEditingRecently()) return;

    ref.read(globalSettingsProvider.notifier).state = g;
    ref.read(globalVolumeProvider.notifier).state = g.globalVolume;
  } finally {
    _pollInFlight = false;
  }
}

/// Sets a device-global dB level ([name] is a `globalCommands` key such as
/// 'inputLevel'/'fxRecLevel'/'btRecLevel'/'monitorLevel'), optimistically
/// updating [globalSettingsProvider]. Not a preset edit. No-op mid-load.
Future<void> setGlobalLevel(WidgetRef ref, String name, int value) async {
  if (ref.read(presetLoadingProvider)) return; // don't edit mid-load

  ref.read(_globalEditAtProvider.notifier).state = DateTime.now();
  final data = ref.read(dataAssetsProvider).valueOrNull;

  if (data == null) return;

  final frame = data.commands.globalCommand(name, value);

  if (frame == null) return;

  // Capture notifiers + the current value BEFORE the await: this runs from the
  // settings dialog, whose WidgetRef is disposed if the dialog closes mid-send,
  // so no `ref` may be touched after the await.
  final settings = ref.read(globalSettingsProvider.notifier);
  final status = ref.read(presetLoadStatusProvider.notifier);
  final current = ref.read(globalSettingsProvider);

  try {
    await ref.read(deviceServiceProvider).sendFrame(frame);
  } catch (e) {
    status.state = 'edit failed: $e';

    return;
  }

  if (current != null) {
    settings.state = switch (name) {
      'inputLevel' => current.copyWith(inputLevel: value),
      'fxRecLevel' => current.copyWith(fxRecLevel: value),
      'btRecLevel' => current.copyWith(btRecLevel: value),
      'monitorLevel' => current.copyWith(monitorLevel: value),
      _ => current,
    };
  }
}

/// Switches the amp slot between Factory amp-models and Clone/User-Profile mode
/// (sends `ampClone`/`ampFactory`), marks the preset modified, then re-reads
/// state. The raw dump only flips the `isCloneMode` bit, but `PresetStateDecoder`
/// *derives* module state from it (it forces IR on in clone mode), so a re-read
/// is needed for the decoded state to be correct. `isCloneMode` is flipped
/// optimistically first so the toggle responds immediately. No-op mid-load.
Future<void> setAmpMode(WidgetRef ref, bool isClone) async {
  if (ref.read(presetLoadingProvider)) return; // don't edit mid-load

  final data = ref.read(dataAssetsProvider).valueOrNull;

  if (data == null) return;

  final frame = isClone ? data.commands.ampClone : data.commands.ampFactory;

  try {
    await ref.read(deviceServiceProvider).sendFrame(frame);
  } catch (e) {
    ref.read(presetLoadStatusProvider.notifier).state = 'edit failed: $e';

    return;
  }

  final st = ref.read(currentPresetStateProvider);

  if (st != null) {
    ref.read(currentPresetStateProvider.notifier).state = st.copyWith(
      isCloneMode: isClone,
      // The decoder forces IR on in clone mode; mirror that optimistically so
      // the IR chip doesn't briefly contradict the toggle before the refresh.
      // (Factory direction: IR reverts to its raw bit, only knowable from the
      // refresh, so leave moduleStates for refreshDecodedState to correct.)
      moduleStates: isClone
          ? {...st.moduleStates, 'IR': true}
          : st.moduleStates,
    );
  }

  ref.read(presetModifiedProvider.notifier).state = true;
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await refreshDecodedState(ref);
  // The AMP slot's editor target changes with the mode (module 3 factory <-> 9
  // clone). Point the editor at the new slot so the AMP editor (which now hosts
  // the Clone Mode toggle) stays open on the amp. Set AFTER the refresh so the
  // editor keeps showing the old amp during the round-trip rather than flashing
  // "no decoded effect"; this update lands in the same rebuild as the decode.
  ref.read(selectedModuleProvider.notifier).state = isClone ? 9 : 3;
}
