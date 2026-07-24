import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/chain_order.dart';
import '../model/preset_json.dart';
import '../protocol/param_value_key.dart';
import '../protocol/preset_field_frame.dart';
import 'data_providers.dart';
import 'device_providers.dart';
import 'file_download.dart';
import 'names_providers.dart';
import 'preset_providers.dart';

/// Exports the current decoded preset to a user-chosen JSON file. No-op if no
/// preset is loaded or the user cancels the dialog.
Future<void> exportPreset(WidgetRef ref) async {
  final data = ref.read(dataAssetsProvider).valueOrNull;
  final state = ref.read(currentPresetStateProvider);

  if (data == null || state == null) return;

  final status = ref.read(presetLoadStatusProvider.notifier);
  final cur = ref.read(currentPresetProvider);
  final name =
      (cur == null ? null : ref.read(presetNamesProvider)[cur]) ??
      cur?.label ??
      'preset';

  final str = const JsonEncoder.withIndent('  ').convert(
    presetToJson(
      state: state,
      selected: ref.read(currentSelectedEffectsProvider),
      params: ref.read(currentParametersProvider),
      data: data,
      presetName: name,
    ),
  );

  try {
    final saved = await saveBytesFile(
      fileName: '${name.replaceAll(RegExp(r'\s+'), '_')}.json',
      bytes: utf8.encode(str),
      dialogTitle: 'Export preset',
      extensions: const ['json'],
    );

    if (saved == null) return; // cancelled

    status.state = 'exported to $saved';
  } catch (e) {
    status.state = 'export failed: $e';
  }
}

/// Imports a preset JSON file and pushes it to the connected pedal (live state
/// only — Save persists it to a slot). Requires a connection.
Future<void> importPreset(WidgetRef ref) async {
  final data = ref.read(dataAssetsProvider).valueOrNull;

  if (data == null) return;

  final status = ref.read(presetLoadStatusProvider.notifier);

  final ImportedPreset imported;

  try {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import preset',
      type: .custom,
      allowedExtensions: const ['json'],
      withData: true,
    );

    final bytes = res?.files.single.bytes;

    if (bytes == null) return; // cancelled

    final str = utf8.decode(bytes);

    imported = importedPresetFromJson(
      jsonDecode(str) as Map<String, dynamic>,
      data,
    );
  } catch (e) {
    status.state = 'import failed: $e';

    return;
  }

  if (ref.read(presetLoadingProvider)) return;

  ref.read(presetLoadingProvider.notifier).state = true;
  final service = ref.read(deviceServiceProvider);
  final c = data.commands;
  var skipped = 0;

  Future<void> send(String? frame) async {
    if (frame == null) {
      skipped++;

      return;
    }

    await service.sendFrame(frame);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  try {
    await send(c.globalCommand('presetVolume', imported.presetVolume));
    // BPM has no captured command — synthesize it (0402 field 2, 16-bit LE).
    await send(
      PresetFieldFrame.build(
        field: PresetFieldFrame.bpmField,
        value: imported.presetBpm,
      ),
    );

    for (final e in imported.moduleStates.entries) {
      await send(e.value ? c.moduleOn(e.key) : c.moduleOff(e.key));
    }

    await send(imported.isCloneMode ? c.ampClone : c.ampFactory);

    for (final e in imported.selectedEffects.entries) {
      await send(c.effectType(e.key, e.value));
    }

    await send(
      c.chainOrderCommand(chainKey(collapseChain(imported.chainOrder))),
    );

    for (final me in imported.parameters.entries) {
      for (final pe in me.value.entries) {
        await send(
          c.parameterCommand(me.key, pe.key, formatParamValueKey(pe.value)),
        );
      }
    }

    await refreshDecodedState(ref);
    ref.read(presetModifiedProvider.notifier).state = true;

    final warn = imported.warnings.isEmpty
        ? ''
        : ' (${imported.warnings.length} warning(s))';

    status.state = 'imported${skipped > 0 ? ', $skipped skipped' : ''}$warn';
  } catch (e) {
    status.state = 'import push failed: $e';
  } finally {
    ref.read(presetLoadingProvider.notifier).state = false;
  }
}
