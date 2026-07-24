import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../state/device_providers.dart';
import '../state/edit_providers.dart';
import '../state/hardware_sync.dart';
import '../state/names_providers.dart';
import '../state/preset_io.dart';
import '../state/preset_providers.dart';
import '../state/reconnect.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'chain_view.dart';
import 'connection_controls.dart';
import 'dev_console_page.dart';
import 'global_settings_dialog.dart';
import 'module_editor.dart';
import 'preset_fields_panel.dart';
import 'preset_rail.dart';
import 'save_preset_dialog.dart';
import 'sonic_controls.dart';
import 'window_controls.dart';

/// Minimum height for the Patch Vol / effect-editor panels, so the Patch Vol
/// knob (value + dial + label) always fits even when the editor has little
/// content (e.g. "no decoded effect").
const _minPanelHeight = 212.0;

/// Minimum laid-out width of the whole app. Desktop enforces a 960-wide window
/// (`minimumSize` in main.dart); the web has no such floor, so below this the
/// app scrolls horizontally rather than overflow — the layout stays intact at
/// its designed minimum. At or above it (always, on desktop) it's a passthrough.
const _minAppWidth = 960.0;

/// Browse the 100 presets and load one onto the pedal. The full pedalboard /
/// parameter editor arrives in Plan 5d; this proves preset selection on device.
class PresetBrowserPage extends HookConsumerWidget {
  const PresetBrowserPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Depend on the surface size so a window resize rebuilds the page. Without
    // this, the post-frame knob-row measurement below only re-runs on a state
    // change: it would latch — e.g. stay stacked after the window widened past
    // the point where the module knobs stopped wrapping.
    MediaQuery.sizeOf(context);

    final hasAutoConnectStarted = useState(false);

    // Dev console: docked at the bottom of the work area, toggled by the topbar
    // terminal icon and closed by its own X. Its height persists for the session
    // and is drag-resizable via the divider grip.
    final isConsoleOpen = useState(false);
    final consoleHeight = useState(260.0);

    // Cross-panel alignment: measured from the effect editor so the Patch Vol
    // panel can match its height and vertically centre its knob on the effect's
    // knob row (whatever header/selects sit above it).
    final editorKey = useMemoized(() => GlobalKey(), const []);
    final knobRowKey = useMemoized(() => GlobalKey(), const []);
    final knobRowTop = useState<double?>(null);
    // Whether the module's knob row wrapped to a second line. When it does, the
    // BPM knob drops below Patch Vol to mirror the two-floor layout; otherwise
    // the two sit side by side. Derived by measurement (below), not guessed.
    final moduleKnobsWrapped = useState(false);
    // The Patch Vol knob cell's height — measured, so the wrap test compares
    // the module knob row against a real single-knob height (both are the same
    // KnobControl(size: panelKnobSize)) instead of a hard-coded pixel guess.
    final patchKnobKey = useMemoized(() => GlobalKey(), const []);

    // Connection heartbeat while connected: detect a silent USB drop (USB has no
    // native connection events) and poll global-settings — the pedal never
    // pushes Master changes (light: one small request; the poll self-skips during
    // edits). Harmless to User-IR flash-commits: a `020100` read never mutates
    // the pedal's IR-commit state (only a `clear` op latches it — see
    // [uploadIr]), and the poll self-suspends for the whole upload+commit window
    // via [presetLoadingProvider].
    useEffect(() {
      final timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(deviceHeartbeat(ref)),
      );

      return timer.cancel;
    }, const []);

    final isConnected = ref.watch(connectionStateProvider);
    final current = ref.watch(currentPresetProvider);
    final isLoading = ref.watch(presetLoadingProvider);
    final state = ref.watch(currentPresetStateProvider);
    final selectedModule = ref.watch(selectedModuleProvider);
    final names = ref.watch(presetNamesProvider);
    final isModified = ref.watch(presetModifiedProvider);

    // Work-area empty state: no device, or a device but no preset selected.
    final emptyMessage = !isConnected
        ? 'No device connected'
        : current == null
        ? 'No preset selected'
        : null;

    // React to a BLE disconnect (drop -> auto-reconnect, unless user-initiated).
    ref.listen(connectionEventsProvider, (prev, next) {
      if (next.value == false) handleConnectionDrop(ref);
    });

    // Mirror device-originated changes (physical footswitch) into the UI.
    ref.listen(inboundProvider, (_, next) {
      next.whenData((m) => handleHardwareSync(ref, m));
    });

    // One-shot: reconnect on launch if the user was connected last session.
    if (!hasAutoConnectStarted.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || hasAutoConnectStarted.value) return;

        hasAutoConnectStarted.value = true;
        autoConnectOnStartup(ref);
      });
    }

    // The two work-panels (Patch Vol + effect editor) are kept the same height
    // by an IntrinsicHeight in the tree below — synchronous, no frame lag. Here
    // we only measure where the editor's knob row sits, so the Patch Vol knob
    // can line up with it vertically. Re-run after each layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      final editorBox =
          editorKey.currentContext?.findRenderObject() as RenderBox?;

      if (editorBox == null || !editorBox.hasSize) return;

      final knobBox =
          knobRowKey.currentContext?.findRenderObject() as RenderBox?;
      final top = (knobBox != null && knobBox.hasSize)
          ? knobBox.localToGlobal(Offset.zero, ancestor: editorBox).dy
          : 12.0; // no knob row (e.g. NR / no decoded effect): sit near the top

      if (knobRowTop.value != top) {
        knobRowTop.value = top;
      }

      // Did the module's knob Wrap spill onto a second line? Compare its box
      // height to one Patch Vol knob (same KnobControl(size: panelKnobSize) as
      // the module knobs). A single row ≈ 1×, two rows ≈ 2×, so 1.4× cleanly
      // separates them without hard-coding the knob's pixel height.
      final patchBox =
          patchKnobKey.currentContext?.findRenderObject() as RenderBox?;

      if (knobBox != null &&
          knobBox.hasSize &&
          patchBox != null &&
          patchBox.hasSize &&
          patchBox.size.height > 0) {
        final wrapped = knobBox.size.height > patchBox.size.height * 1.4;

        if (moduleKnobsWrapped.value != wrapped) {
          moduleKnobsWrapped.value = wrapped;
        }
      }
    });

    return ColoredBox(
      color: Palette.background,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Below the desktop minimum width, scroll the whole app horizontally
            // instead of overflowing; at or above it, pass straight through.
            final width = math.max(constraints.maxWidth, _minAppWidth);

            final app = SizedBox(
              width: width,
              child: Column(
                children: [
                  // shared "convex plastic" top bar spanning the rail + work area:
                  // branding over the rail, connection controls + preset name +
                  // actions over the work area.
                  TopBarDragArea(
                    child: SizedBox(
                      height: 60,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF3E3E3E),
                              Color(0xFF242424),
                              Color(0xFF0A0A0A),
                            ],
                            stops: [0.0, 0.4, 1.0],
                          ),
                          border: Border(
                            top: BorderSide(
                              color: Color(0x18FFFFFF),
                            ), // specular edge
                            bottom: BorderSide(
                              color: Color(0xFF000000),
                            ), // convex plastic lip
                          ),
                        ),
                        child: Row(
                          children: [
                            // rail zone — logo; the zone is railWidth wide (matches the
                            // rail below) and the logo is bounded by a horizontal inset
                            // so it never crosses the rail/browser divider at railWidth.
                            Container(
                              width: railWidth,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                height: 40,
                                child: SvgPicture.asset(
                                  'assets/images/logo.svg',
                                  fit: .contain,
                                  alignment: Alignment.centerLeft,
                                  colorFilter: const ColorFilter.mode(
                                    Palette.textPrimary,
                                    .srcIn,
                                  ),
                                ),
                              ),
                            ),
                            // work-area zone — preset name aligned to the rail/work-area
                            // divider, inset by the same padding as the bar's right edge;
                            // connection cluster + action icons pinned right
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    if (isConnected && current != null)
                                      SonicRecess(
                                        radius: 8,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          mainAxisSize: .min,
                                          children: [
                                            PresetSlotChip(current.label),
                                            if ((names[current] ?? '')
                                                .isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      maxWidth: 220,
                                                    ),
                                                child: Text(
                                                  names[current]!,
                                                  maxLines: 1,
                                                  overflow: .ellipsis,
                                                  style: AppText.presetTitle
                                                      .copyWith(
                                                        color:
                                                            Palette.textPrimary,
                                                      ),
                                                ),
                                              ),
                                            ],
                                            // Unsaved-edits marker, kept outside the
                                            // ellipsizing name box so a long name can't
                                            // truncate it.
                                            if (isModified) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '✱',
                                                style: AppText.presetTitle
                                                    .copyWith(
                                                      color:
                                                          Palette.textPrimary,
                                                    ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    const Spacer(),
                                    SonicIconButton(
                                      icon: Icons.tune,
                                      onPressed: (isConnected && !isLoading)
                                          ? () {
                                              refreshGlobalSettings(ref);
                                              showSonicDialog<void>(
                                                context: context,
                                                builder: (_) =>
                                                    const GlobalSettingsDialog(),
                                              );
                                            }
                                          : null,
                                    ),
                                    SonicIconButton(
                                      icon: Icons.file_upload,
                                      onPressed: (isConnected && state != null)
                                          ? () => exportPreset(ref)
                                          : null,
                                    ),
                                    SonicIconButton(
                                      icon: Icons.file_download,
                                      onPressed: (isConnected && !isLoading)
                                          ? () => importPreset(ref)
                                          : null,
                                    ),
                                    SonicIconButton(
                                      icon: Icons.save,
                                      onPressed:
                                          (isConnected &&
                                              !isLoading &&
                                              current != null)
                                          ? () => showSonicDialog<bool>(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (_) =>
                                                  const SavePresetDialog(),
                                            )
                                          : null,
                                    ),
                                    // Developer/protocol-RE console — debug builds only.
                                    // It streams raw MIDI and writes a capture log to
                                    // disk, so it must never ship in a release build.
                                    if (kDebugMode)
                                      SonicIconButton(
                                        icon: Icons.terminal,
                                        color: isConsoleOpen.value
                                            ? Palette.accent
                                            : null,
                                        onPressed: () => isConsoleOpen.value =
                                            !isConsoleOpen.value,
                                      ),
                                    const SizedBox(width: 12),
                                    // Connection status, pinned to the right edge.
                                    const SonicRecess(
                                      radius: 8,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      child: ConnectionControls(),
                                    ),
                                    if (isDesktopWindow)
                                      const SizedBox(width: 8),
                                    if (isDesktopWindow) const WindowControls(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      // Stretch so the work area fills its full height (its grey plate
                      // covers everything and the content top-aligns).
                      crossAxisAlignment: .stretch,
                      children: [
                        const PresetRail(),
                        Expanded(
                          // Recessed work area: a grey plate, darker than the rail but
                          // filling the whole panel, with the top bar's shadow cast along
                          // its top edge only (the rail, on the bar's own plane, gets none).
                          child: DecoratedBox(
                            // TEMP swap: work area uses the rail's grey gradient.
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFF3A3A3A), Color(0xFF2A2A2A)],
                              ),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                const dividerHeight = 16.0;
                                const minConsoleHeight = 220.0;
                                const minEditorHeight = 180.0;

                                final rawMax =
                                    constraints.maxHeight -
                                    dividerHeight -
                                    minEditorHeight;
                                final maxHeight = rawMax < minConsoleHeight
                                    ? minConsoleHeight
                                    : rawMax;
                                final effectiveHeight = consoleHeight.value
                                    .clamp(minConsoleHeight, maxHeight);

                                return Column(
                                  crossAxisAlignment: .stretch,
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          LayoutBuilder(
                                            builder: (context, constraints) => SingleChildScrollView(
                                              padding: const EdgeInsets.all(12),
                                              // Center the work-area content vertically (grows past
                                              // the viewport → scrolls). Clone Mode moved into the
                                              // AMP editor, matching the web app.
                                              child: ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  minHeight:
                                                      constraints.maxHeight -
                                                      24,
                                                ),
                                                child: Column(
                                                  mainAxisAlignment: .center,
                                                  crossAxisAlignment: .stretch,
                                                  children: [
                                                    if (emptyMessage != null)
                                                      Text(
                                                        emptyMessage,
                                                        textAlign: .center,
                                                        style: AppText
                                                            .dialogTitle
                                                            .copyWith(
                                                              color: Palette
                                                                  .textDim,
                                                            ),
                                                      )
                                                    else if (state != null) ...[
                                                      const ChainView(),
                                                      const SizedBox(
                                                        height: 34,
                                                      ),
                                                      // Compact Patch Vol knob (left, top-aligned) + effect
                                                      // editor (fills the rest; placeholder when nothing is
                                                      // selected). Both always shown once a preset is loaded,
                                                      // at a fixed equal height (the editor scrolls if a
                                                      // param-heavy effect is taller).
                                                      // Patch Vol knob vertically aligned with the
                                                      // effect's knob row; both panels the same height
                                                      // (measured from the editor — see the post-frame
                                                      // alignment above).
                                                      // Both panels the SAME height via IntrinsicHeight
                                                      // + stretch (synchronous — no post-frame height
                                                      // measurement to lag behind content changes).
                                                      IntrinsicHeight(
                                                        child: Row(
                                                          crossAxisAlignment:
                                                              .stretch,
                                                          children: [
                                                            PresetFieldsPanel(
                                                              presetVolume: state
                                                                  .presetVolume,
                                                              presetBpm: state
                                                                  .presetBpm,
                                                              isLoading:
                                                                  isLoading,
                                                              topSpacer:
                                                                  knobRowTop
                                                                      .value ??
                                                                  12,
                                                              stacked:
                                                                  moduleKnobsWrapped
                                                                      .value,
                                                              patchKnobKey:
                                                                  patchKnobKey,
                                                              onVolume: (v) =>
                                                                  setPresetVolume(
                                                                    ref,
                                                                    v,
                                                                  ),
                                                              onBpm: (v) =>
                                                                  setPresetBpm(
                                                                    ref,
                                                                    v,
                                                                  ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Expanded(
                                                              child: ConstrainedBox(
                                                                constraints:
                                                                    const BoxConstraints(
                                                                      minHeight:
                                                                          _minPanelHeight,
                                                                    ),
                                                                child: SonicSurface(
                                                                  key:
                                                                      editorKey,
                                                                  padding:
                                                                      EdgeInsets
                                                                          .zero,
                                                                  // Always a selection (default NR).
                                                                  child: ModuleEditor(
                                                                    selectedModule ??
                                                                        0,
                                                                    knobRowKey:
                                                                        knobRowKey,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const Positioned(
                                            top: 0,
                                            left: 0,
                                            right: 0,
                                            height: 16,
                                            child: IgnorePointer(
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      Color(0x66000000),
                                                      Color(0x00000000),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (kDebugMode && isConsoleOpen.value) ...[
                                      _ConsoleResizeHandle(
                                        onDrag: (dy) => consoleHeight.value =
                                            (consoleHeight.value - dy).clamp(
                                              minConsoleHeight,
                                              maxHeight,
                                            ),
                                      ),
                                      SizedBox(
                                        height: effectiveHeight,
                                        child: DevConsolePanel(
                                          onClose: () =>
                                              isConsoleOpen.value = false,
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );

            if (width <= constraints.maxWidth) return app;

            return SingleChildScrollView(
              scrollDirection: .horizontal,
              child: app,
            );
          },
        ),
      ),
    );
  }
}

/// The draggable divider between the work area and the docked dev console:
/// a full-width bar carrying the same [DragGrip] as the module cards, with a
/// resize cursor. [onDrag] receives the vertical drag delta (dy).
class _ConsoleResizeHandle extends StatelessWidget {
  const _ConsoleResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: .opaque,
        onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Palette.railBorder)),
          ),
          child: SizedBox(height: 16, child: Center(child: DragGrip())),
        ),
      ),
    );
  }
}
