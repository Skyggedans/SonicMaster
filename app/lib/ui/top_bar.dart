import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../state/device_providers.dart';
import '../state/names_providers.dart';
import '../state/preset_io.dart';
import '../state/preset_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'connection_controls.dart';
import 'fullscreen_button.dart';
import 'global_settings_dialog.dart';
import 'preset_rail.dart';
import 'save_preset_dialog.dart';
import 'sonic_controls.dart';
import 'sonic_metrics.dart';
import 'window_controls.dart';

/// The title bar's "convex plastic" plate: a dark top-to-bottom gradient with a
/// specular top edge and a black lip. The compact preset drawer's header wears
/// the same plate, so the open drawer reads as part of the bar.
const topBarDecoration = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF3E3E3E), Color(0xFF242424), Color(0xFF0A0A0A)],
    stops: [0.0, 0.4, 1.0],
  ),
  border: Border(
    top: BorderSide(color: Color(0x18FFFFFF)), // specular edge
    bottom: BorderSide(color: Color(0xFF000000)), // convex plastic lip
  ),
);

/// Width of the compact title bar's leading slot. The compact preset drawer
/// floats its burger into this slot, above its sliding panel, so the button
/// never moves while the drawer opens or closes.
const drawerButtonSlotWidth = 48.0;

/// The SONICMASTER wordmark in the primary text colour: the regular title
/// bar's logo zone and the compact preset drawer's header.
class SonicLogo extends StatelessWidget {
  const SonicLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: SvgPicture.asset(
        'assets/images/logo.svg',
        fit: .contain,
        alignment: Alignment.centerLeft,
        colorFilter: const ColorFilter.mode(Palette.textPrimary, .srcIn),
      ),
    );
  }
}

/// The shared "convex plastic" title bar spanning the rail and the work area:
/// branding over the rail, then the loaded preset, the actions and the
/// connection well over the work area. On desktop it also drags the window and
/// carries the window controls.
///
/// Compact: 48 px tall, an empty leading slot the preset drawer floats its
/// burger into instead of the logo zone, a preset well that gives way to the
/// actions, no console toggle and a connection well without its label.
///
/// The actions run on this widget's own ref and context, so an import or a
/// connect in flight survives anything that rebuilds the page around the bar.
class TopBar extends ConsumerWidget {
  const TopBar({
    super.key,
    required this.isConsoleOpen,
    required this.onConsoleToggle,
  });

  /// Whether the debug console is docked open (tints its toggle).
  final bool isConsoleOpen;

  /// Opens or closes the debug console (debug builds only).
  final VoidCallback onConsoleToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = SonicMetrics.of(context);
    final isCompact = metrics.isCompact;
    final isConnected = ref.watch(connectionStateProvider);
    final current = ref.watch(currentPresetProvider);
    final isLoading = ref.watch(presetLoadingProvider);
    final state = ref.watch(currentPresetStateProvider);
    final names = ref.watch(presetNamesProvider);
    final isModified = ref.watch(presetModifiedProvider);

    final well = (isConnected && current != null)
        ? _PresetWell(
            slot: current.label,
            name: names[current] ?? '',
            isModified: isModified,
            isCompact: isCompact,
          )
        : null;

    return TopBarDragArea(
      child: SizedBox(
        height: metrics.topBarHeight,
        child: Container(
          decoration: topBarDecoration,
          child: Row(
            children: [
              // Regular: the logo zone over the rail. Compact: an empty slot
              // the preset drawer floats its burger into (the burger has to
              // sit above the drawer's panel, so it can't live in this bar).
              if (isCompact)
                const SizedBox(width: drawerButtonSlotWidth)
              else
                const _LogoZone(),
              // work-area zone — preset name aligned to the rail/work-area
              // divider, inset by the same padding as the bar's right edge;
              // connection cluster + action icons pinned right
              Expanded(
                child: Padding(
                  padding: isCompact
                      ? const EdgeInsets.only(right: 8)
                      : const EdgeInsets.symmetric(horizontal: 16),
                  // ONE flat row in both layouts whose trailing items (the
                  // actions, the gap, the connection well, the window
                  // controls) match from the end: a layout flip updates them
                  // in place, so the connection well keeps its element and
                  // its ref through a connect in flight. Never group them.
                  child: Row(
                    children: [
                      if (isCompact) ...[
                        // The well gives way to the actions: its name
                        // ellipsizes first.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: well,
                          ),
                        ),
                        const FullscreenButton(),
                      ] else ...[
                        ?well,
                        const Spacer(),
                      ],
                      SonicIconButton(
                        icon: Icons.tune,
                        padding: metrics.topBarIconPadding,
                        onPressed: (isConnected && !isLoading)
                            ? () {
                                refreshGlobalSettings(ref);
                                showSonicDialog<void>(
                                  context: context,
                                  builder: (_) => const GlobalSettingsDialog(),
                                );
                              }
                            : null,
                      ),
                      // Export writes the preset out to a file on disk (arrow
                      // down, "save"); import reads a file in and pushes it to
                      // the pedal (arrow up).
                      SonicIconButton(
                        icon: Icons.file_download,
                        padding: metrics.topBarIconPadding,
                        onPressed: (isConnected && state != null)
                            ? () => exportPreset(ref)
                            : null,
                      ),
                      SonicIconButton(
                        icon: Icons.file_upload,
                        padding: metrics.topBarIconPadding,
                        onPressed: (isConnected && !isLoading)
                            ? () => importPreset(ref)
                            : null,
                      ),
                      SonicIconButton(
                        icon: Icons.save,
                        padding: metrics.topBarIconPadding,
                        onPressed:
                            (isConnected && !isLoading && current != null)
                            ? () => showSavePresetDialog(context)
                            : null,
                      ),
                      // Developer/protocol-RE console — debug builds only. It
                      // streams raw MIDI and writes a capture log to disk, so it
                      // must never ship in a release build. The compact page
                      // has no room to dock it.
                      if (kDebugMode && !isCompact)
                        SonicIconButton(
                          icon: Icons.terminal,
                          padding: metrics.topBarIconPadding,
                          color: isConsoleOpen ? Palette.accent : null,
                          onPressed: onConsoleToggle,
                        ),
                      SizedBox(width: isCompact ? 8 : 12),
                      // Connection status, pinned to the right edge.
                      // Compact: the whole well, stretched to the bar's
                      // height, connects while disconnected (the 26-px button
                      // alone is small for a finger). It never disconnects:
                      // Disconnect stays on its button. Wrapped in every
                      // layout and state (inert in regular), so
                      // ConnectionControls keeps its element and its ref
                      // through connects, disconnects and mode flips.
                      SonicHitArea(
                        onTap: metrics.isCompact
                            ? connectAction(context, ref)
                            : null,
                        child: SizedBox(
                          height: double.infinity,
                          child: Center(
                            widthFactor: 1,
                            child: SonicRecess(
                              radius: 8,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: ConnectionControls(
                                hasStatusLabel: !metrics.isCompact,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (isDesktopWindow) const SizedBox(width: 8),
                      if (isDesktopWindow) const WindowControls(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The regular bar's branding zone: as wide as the rail below it, the logo
/// inset so it never crosses the rail/work-area divider.
class _LogoZone extends StatelessWidget {
  const _LogoZone();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: railWidth,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: const SonicLogo(),
    );
  }
}

/// The loaded preset in a recessed well: its slot chip, its decoded name (if
/// any) and the unsaved-edits marker.
class _PresetWell extends StatelessWidget {
  const _PresetWell({
    required this.slot,
    required this.name,
    required this.isModified,
    required this.isCompact,
  });

  final String slot;
  final String name;
  final bool isModified;

  /// Compact: the well sits in a bounded slot and its name gives way
  /// (ellipsizes) when the bar runs short. Regular lays the well out at its
  /// natural width (unbounded), where a Flexible would throw.
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final nameBox = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(
        name,
        maxLines: 1,
        overflow: .ellipsis,
        style: AppText.presetTitle.copyWith(color: Palette.textPrimary),
      ),
    );

    return SonicRecess(
      radius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: .min,
        children: [
          PresetSlotChip(slot),
          if (name.isNotEmpty) ...[
            const SizedBox(width: 8),
            if (isCompact) Flexible(child: nameBox) else nameBox,
          ],
          // Unsaved-edits marker, kept outside the ellipsizing name box so a
          // long name can't truncate it. "✱" is not in Oswald: the forced
          // Oswald strut keeps its fallback face's taller line from growing
          // the well.
          if (isModified) ...[
            const SizedBox(width: 6),
            Text(
              '✱',
              strutStyle: StrutStyle.fromTextStyle(
                AppText.presetTitle,
                forceStrutHeight: true,
              ),
              style: AppText.presetTitle.copyWith(color: Palette.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}
