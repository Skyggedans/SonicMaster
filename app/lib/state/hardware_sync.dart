import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/preset_ref.dart';
import '../protocol/inbound_message.dart';
import 'data_providers.dart';
import 'names_providers.dart';
import 'preset_providers.dart';

/// A device-originated change worth mirroring into the UI.
sealed class HardwareSyncEvent {}

/// The pedal loaded a different preset (physical footswitch); [preset] is the
/// new slot.
class PresetSelected extends HardwareSyncEvent {
  PresetSelected(this.preset);
  final PresetRef preset;
}

/// The pedal broadcast a full preset-state dump ([frameHex], `01020401`).
class StateDump extends HardwareSyncEvent {
  StateDump(this.frameHex);
  final String frameHex;
}

/// The pedal reported a single footswitch toggle made ON the pedal (`12 4D`):
/// [module]'s membership on one switch changed. [isFs2] picks the switch
/// (false = FS1, true = FS2); [isOn] is its new state. Only that switch's bit
/// moves — the pedal allows a module on both switches, so the other is left be.
class FootswitchChanged extends HardwareSyncEvent {
  FootswitchChanged({
    required this.module,
    required this.isFs2,
    required this.isOn,
  });

  final int module;
  final bool isFs2;
  final bool isOn;
}

/// The pedal reported a single module enabled/disabled ON the pedal — the
/// `01020409` broadcast (the `0102040X` "report" family, like the `0102040D`
/// footswitch report). [module] is the physical slot; [isOn] its new state.
class ModuleToggled extends HardwareSyncEvent {
  ModuleToggled({required this.module, required this.isOn});

  final int module;
  final bool isOn;
}

/// Maps an inbound [m] to a device-originated change to mirror, or null to
/// ignore. Content-based (never timing); only `DataFrame`s carry state.
HardwareSyncEvent? classifyHardwareSync(InboundMessage m) {
  if (m is! DataFrame) return null;

  final hex = m.hex.toUpperCase();

  // module enable/disable toggled ON the pedal:
  // 8080F0 <crc><prefix> 01020409 00 <module> 00×7 <state> 00×6 F7. Same 32-byte
  // shape as the app's own `01010409` enable command, but the pedal broadcasts
  // the `0102040X` report variant. `state` 1 = on; `module` is one byte.
  if (hex.length >= 50 && hex.substring(22, 30) == '01020409') {
    final module = int.parse(hex.substring(32, 34), radix: 16);

    if (module > 15) return null;

    return ModuleToggled(
      module: module,
      isOn: int.parse(hex.substring(48, 50), radix: 16) != 0,
    );
  }

  // footswitch toggle report, pushed when a switch is changed ON the pedal:
  // 8080 F0 <crc4> 0001 0000 0005 0102040D <switch> <module> <state> F7. `switch`
  // 0 = FS1 / 1 = FS2; `state` 1 = on. Each value is one byte in expanded nibble
  // form (`00 0V`), so its 4-hex group parses straight to the integer.
  if (hex.length >= 44 && hex.substring(10, 30) == '0001000000050102040D') {
    final module = int.parse(hex.substring(34, 38), radix: 16);

    if (module > 15) return null;

    return FootswitchChanged(
      module: module,
      isFs2: int.parse(hex.substring(30, 34), radix: 16) != 0,
      isOn: int.parse(hex.substring(38, 42), radix: 16) != 0,
    );
  }

  // preset-select notify: 8080F0 <crc4> 00 01000000 06 01 020403 <hi><lo> ...
  // <hi><lo> is a plain global preset index (verified off the device: U01 = 00
  // 00, F01 = 03 02 = 50), matching PresetRef.all() order (User 0–49, Factory
  // 50–99). (The old `(hi-3)*16` offset was wrong — it dropped U01 and shifted
  // banks.)
  if (hex.length >= 34 && hex.substring(24, 30) == '020403') {
    final index =
        int.parse(hex.substring(30, 32), radix: 16) * 16 +
        int.parse(hex.substring(32, 34), radix: 16);

    final all = PresetRef.all();

    if (index < 0 || index >= all.length) return null;

    return PresetSelected(all[index]);
  }

  // full preset-state dump — same signature the app's own state-dump uses.
  if (hex.length >= 30 && hex.substring(22, 30) == '01020401') {
    return StateDump(hex);
  }

  return null;
}

/// Debounce for the state re-read triggered by the pedal's content-less
/// "preset modified" notify. One device → a single shared timer. Rapid on-pedal
/// edits (and any echo of the app's own writes) coalesce into one re-read after
/// the edits settle.
Timer? _modifiedDebounce;

/// How long to wait after the last "modified" notify before re-reading state.
const _modifiedRereadDelay = Duration(milliseconds: 300);

/// Reacts to a device-originated change by pulling the current state into the
/// UI. The pedal notifies *that* something changed but the notify carries no
/// content, so — beyond the two `DataFrame` broadcasts (preset-select /
/// full state dump) — we re-read state on the "preset modified" flag too. The
/// re-read ([refreshDecodedState]) reads the device but sends no edit command,
/// so this cannot create a write feedback loop.
void handleHardwareSync(WidgetRef ref, InboundMessage m) {
  // On-pedal parameter edit: a content-less "modified" flag (the pedal does NOT
  // push a state dump per edit). Mark modified and debounce a re-read to pull
  // the actual value.
  if (m is PresetModifiedMessage) {
    ref.read(presetModifiedProvider.notifier).state = true;
    _scheduleModifiedReread(ref);

    return;
  }

  // An on-pedal edit can also CLEAR the dirty flag — e.g. toggling a module back
  // to its saved value returns the preset to the stored state, so the pedal
  // sends "saved" (…050000) instead of "modified" (…050001). Without re-reading
  // here the UI keeps the pre-edit value — the "turn a module off, then on, and
  // it never lights up again" bug. Re-read to pull the real state, but mark it
  // clean. (The app's own save brackets its I/O with `presetLoadingProvider`, so
  // the re-read self-skips there — this only fires for device-originated saves.)
  if (m is PresetSavedMessage) {
    ref.read(presetModifiedProvider.notifier).state = false;
    _scheduleModifiedReread(ref);

    return;
  }

  switch (classifyHardwareSync(m)) {
    case null:
      return;
    case PresetSelected(:final preset):
      ref.read(currentPresetProvider.notifier).state = preset;
      // Follow the pedal's bank so the rail lists (and highlights) the new
      // preset instead of filtering it out on the other tab.
      ref.read(presetTabProvider.notifier).state = preset.bank;
      ref.read(presetModifiedProvider.notifier).state = false;
      // A pending "modified" re-read is for the old preset — supersede it.
      _modifiedDebounce?.cancel();

      // The notify carries only the slot, so pull the new preset's content
      // (effects / params / chain), unless a load is already fetching it.
      if (!ref.read(presetLoadingProvider)) {
        unawaited(refreshDecodedState(ref));
      }
    case StateDump(:final frameHex):
      final data = ref.read(dataAssetsProvider).valueOrNull;

      if (data != null) applyDecodedDump(ref, data, frameHex);
    case FootswitchChanged(:final module, :final isFs2, :final isOn):
      // Instant feedback for an on-pedal switch toggle: flip just this module's
      // bit in the reported switch's mask. (The accompanying "modified" notify
      // still fires, but this doesn't wait on its re-read.)
      final st = ref.read(currentPresetStateProvider);

      if (st == null) return;

      final bit = 1 << module;
      var fs1 = st.footswitchFs1Mask;
      var fs2 = st.footswitchFs2Mask;

      if (isFs2) {
        fs2 = isOn ? fs2 | bit : fs2 & ~bit;
      } else {
        fs1 = isOn ? fs1 | bit : fs1 & ~bit;
      }

      ref.read(currentPresetStateProvider.notifier).state = st
          .withFootswitchMasks(fs1Mask: fs1, fs2Mask: fs2);
    case ModuleToggled(:final module, :final isOn):
      // Instant feedback for an on-pedal module on/off: flip just this module's
      // enabled state. (The accompanying "modified"/"saved" notify still fires
      // and re-reads to confirm, but this doesn't wait on it — the report used
      // to be dropped entirely, so the indicator never lit back up.)
      final st = ref.read(currentPresetStateProvider);
      final name = ref
          .read(dataAssetsProvider)
          .valueOrNull
          ?.modules
          .nameOf(module);

      if (st == null || name == null) return;

      ref.read(currentPresetStateProvider.notifier).state = st.copyWith(
        moduleStates: {...st.moduleStates, name: isOn},
      );
  }
}

void _scheduleModifiedReread(WidgetRef ref) {
  if (ref.read(presetLoadingProvider)) return; // don't fight an in-flight load

  _modifiedDebounce?.cancel();
  _modifiedDebounce = Timer(_modifiedRereadDelay, () {
    if (!ref.read(presetLoadingProvider)) unawaited(refreshDecodedState(ref));
  });
}
