import 'dart:async';

import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../model/command_library.dart';
import '../model/preset_ref.dart';
import '../state/device_providers.dart';
import '../state/names_providers.dart';
import '../state/preset_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'knob_control.dart';
import 'sonic_controls.dart';
import 'sonic_field.dart';
import 'unsaved_changes_dialog.dart';

const railWidth = 244.0;

TextStyle _railStyle(
  double size, {
  FontWeight w = FontWeight.w500,
  Color? color,
  double ls = 0,
}) => AppText.railHeader.copyWith(
  fontSize: size,
  fontWeight: w,
  color: color ?? Palette.railText,
  letterSpacing: ls,
);

/// A compact accent "chip" for a preset slot number (e.g. P01), shown in the
/// top bar and the preset list in place of a "P01:" text prefix.
class PresetSlotChip extends StatelessWidget {
  const PresetSlotChip(this.slot, {super.key});

  final String slot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: Palette.accent,
      ),
      child: Text(
        slot,
        style: AppText.railHeader.copyWith(
          color: Color(0xFFFFFFFF),
          height: 1.15,
        ),
      ),
    );
  }
}

/// One preset row in the rail's chip list: a [PresetSlotChip] plus the decoded
/// name (if any). Selected → orange border + tint; disabled → dimmed, no tap.
class PresetChip extends StatelessWidget {
  const PresetChip({
    super.key,
    required this.slot,
    this.name,
    required this.isSelected,
    required this.isEnabled,
    this.onTap,
  });

  final String slot;
  final String? name;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = name;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Opacity(
        opacity: isEnabled ? 1 : 0.4,
        child: GestureDetector(
          onTap: isEnabled ? onTap : null,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: isSelected
                  ? const Color(0x33FF6B35)
                  : Color(0xFFFFFFFF).withValues(alpha: 0.05),
              border: Border.all(
                color: isSelected ? Palette.accent : Color(0x00000000),
              ),
            ),
            child: Row(
              children: [
                PresetSlotChip(slot),
                if (n != null && n.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      n,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: _railStyle(14),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A Factory/User tab button; active → orange text + orange bottom border.
class RailTab extends StatelessWidget {
  const RailTab({
    super.key,
    required this.label,
    required this.isActive,
    this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF2A2A2A) : const Color(0xFF333333),
            border: Border(
              bottom: BorderSide(
                color: isActive ? Palette.accent : const Color(0xFF333333),
                width: 2,
              ),
            ),
          ),
          child: Text(
            label.toUpperCase(),
            style: _railStyle(
              11,
              color: isActive ? Palette.accent : Palette.railMuted,
              ls: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width rail button; primary → accent gradient, else neutral.
class RailButton extends StatelessWidget {
  const RailButton({
    super.key,
    required this.label,
    this.isPrimary = false,
    this.isEnabled = true,
    this.onTap,
  });

  final String label;
  final bool isPrimary;
  final bool isEnabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isEnabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: isEnabled ? onTap : null,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isPrimary
                  ? const [Palette.accent, Color(0xFFE0550A)]
                  : const [Color(0xFF4A4A4A), Color(0xFF3A3A3A)],
            ),
          ),
          child: Text(
            label.toUpperCase(),
            style: _railStyle(11, w: .w600, ls: 0.8),
          ),
        ),
      ),
    );
  }
}

/// The left sidebar: the Connect/Disconnect action at the top, and — once
/// connected — the master-volume knob plus the tabbed, searchable preset chip
/// list. Connect opens the USB/BLE device picker; the connection-status
/// indicator lives in the top bar ([ConnectionControls]).
class PresetRail extends ConsumerWidget {
  const PresetRail({super.key});

  Future<void> _load(BuildContext context, WidgetRef ref, PresetRef p) async {
    if (ref.read(presetModifiedProvider) &&
        !await showUnsavedChangesDialog(context)) {
      return; // user cancelled — keep edits
    }

    await loadPreset(ref, p);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(connectionStateProvider);
    final isLoading = ref.watch(presetLoadingProvider);
    final globalVol = ref.watch(globalVolumeProvider);
    final current = ref.watch(currentPresetProvider);
    final names = ref.watch(presetNamesProvider);
    final query = ref.watch(presetSearchProvider);
    final tab = ref.watch(presetTabProvider);
    final chips = PresetRef.all()
        .where((p) => p.bank == tab && presetMatchesQuery(p, query, names))
        .toList();

    return Container(
      width: railWidth,
      decoration: const BoxDecoration(
        // TEMP swap: rail uses the work-area grey (was the #3A→#2A gradient).
        color: Color(0xFF272727),
        border: Border(right: BorderSide(color: Palette.railBorder)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          // Connect/Disconnect now lives in the top bar's device well; the rail
          // shows the master knob + preset browser only when connected.
          if (isConnected) ...[
            // master volume — our rotary knob
            Padding(
              padding: const EdgeInsets.all(14),
              child: KnobControl(
                value: globalVol,
                min: 0,
                max: 100,
                step: 1,
                label: 'Master Vol',
                isEnabled: !isLoading,
                onChanged: (v) => setGlobalVolume(ref, v.round()),
              ),
            ),
            // thin rail divider — same hairline as the footer's top border,
            // separating the master knob from the bank selector. Only present
            // while connected (this whole block is gated on isConnected).
            Container(height: 1, color: Palette.railBorder),
            // bank tabs
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: SonicSegmented<PresetBank>(
                value: tab,
                isExpanded: true,
                height: 40,
                segments: const [
                  (value: PresetBank.factory, label: 'Factory'),
                  (value: PresetBank.user, label: 'User'),
                ],
                onChanged: (b) =>
                    ref.read(presetTabProvider.notifier).state = b,
              ),
            ),
            // search — a grey recessed well (rail-toned), borderless.
            // Extra top padding gives a harmonious gap below the selector.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
              child: const _PresetSearchField(),
            ),
            // chip list
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: ListView(
                  children: [
                    for (final p in chips)
                      PresetChip(
                        slot: p.label,
                        name: names[p],
                        isSelected: current == p,
                        isEnabled: isConnected && !isLoading,
                        onTap: () => _load(context, ref, p),
                      ),
                  ],
                ),
              ),
            ),
          ] else
            const Spacer(),
          const _RailFooter(),
        ],
      ),
    );
  }
}

/// The rail's persistent footer: the app name + version and author credit,
/// pinned to the bottom of the rail in every connection state. Reads the bundle
/// version at runtime, so it tracks the pubspec without a hardcoded string.
class _RailFooter extends HookWidget {
  const _RailFooter();

  @override
  Widget build(BuildContext context) {
    final info = useFuture(useMemoized(PackageInfo.fromPlatform));
    final version = info.data?.version ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.railBorder)),
      ),
      child: Column(
        children: [
          Text(
            version.isEmpty ? 'SonicMaster' : 'SonicMaster $version',
            textAlign: .center,
            style: _railStyle(11, w: .w600, ls: 0.5),
          ),
          const SizedBox(height: 2),
          Text(
            'by Skyggedans',
            textAlign: .center,
            style: _railStyle(10, color: Palette.railMuted, ls: 0.5),
          ),
        ],
      ),
    );
  }
}

/// The rail's preset search box: a rail-toned recessed well with a leading
/// search glyph and a [SonicField] that pushes typed text into
/// [presetSearchProvider] (which drives the chip-list filter).
class _PresetSearchField extends HookConsumerWidget {
  const _PresetSearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();

    return SonicRecess(
      radius: 8,
      colors: const [Color(0xFF1E1E1E), Color(0xFF2A2A2A)],
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: Color(0xFF9A9488)),
          const SizedBox(width: 8),
          Expanded(
            child: SonicField(
              controller: controller,
              hintText: 'Search presets',
              style: AppText.input.copyWith(
                color: Palette.railText,
                fontSize: 14,
              ),
              isRecessed: false,
              padding: const EdgeInsets.symmetric(vertical: 11),
              onChanged: (v) =>
                  ref.read(presetSearchProvider.notifier).state = v,
            ),
          ),
        ],
      ),
    );
  }
}
