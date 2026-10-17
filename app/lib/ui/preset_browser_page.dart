import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../model/preset_ref.dart';
import '../state/device_providers.dart';
import '../state/edit_providers.dart';
import '../state/hardware_sync.dart';
import '../state/layout_providers.dart';
import '../state/preset_providers.dart';
import '../state/reconnect.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'chain_view.dart';
import 'dev_console_page.dart';
import 'module_editor.dart';
import 'preset_drawer.dart';
import 'preset_fields_panel.dart';
import 'preset_rail.dart';
import 'sonic_controls.dart';
import 'sonic_metrics.dart';
import 'top_bar.dart';

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

    // The layout's size tokens (the app frame publishes them above the
    // Navigator). Compact (phones): no rail, no dev console, a narrower floor.
    final metrics = SonicMetrics.of(context);

    // Compact: the app ends above the soft keyboard (mobile browsers fill
    // viewInsets while a field is edited), so a focused field's own
    // show-on-screen can scroll it into view. This page is the inset's only
    // owner (the drawer never pads itself; dialogs lift themselves). Regular
    // never resizes and takes no viewInsets dependency.
    final keyboardInset = metrics.isCompact
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;

    // Preset picks and Master Vol writes run on the page's own context and
    // ref, which outlive every layout flip: the rail (and, compact, the
    // drawer) unmount on a flip, and a load or a level write running on their
    // ref would throw mid-flight. The rail and the drawer stay identical
    // across builds, so a page rebuild (every Patch Vol drag step) skips the
    // rail's 50 rows.
    final pick = useCallback(
      (PresetRef preset) => unawaited(pickPreset(context, ref, preset)),
      const [],
    );

    final setMasterVolume = useCallback(
      (int value) => unawaited(setGlobalVolume(ref, value)),
      const [],
    );

    final rail = useMemoized(
      () => PresetRail(onPick: pick, onMasterVolume: setMasterVolume),
      const [],
    );

    final drawer = useMemoized(
      () => PresetDrawer(onPick: pick, onMasterVolume: setMasterVolume),
      const [],
    );

    // Leaving compact closes the drawer for good: it unmounts with the layout
    // and must not come back open the next time the viewport turns compact.
    // Deferred past this build: a provider can't change while widgets build.
    final wasCompact = usePrevious(metrics.isCompact) ?? false;

    if (wasCompact && !metrics.isCompact) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref.read(presetDrawerOpenProvider.notifier).state = false;
        }
      });
    }

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
    // metrics.panelKnobSize dial) instead of a hard-coded pixel guess.
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
      // height to one Patch Vol knob (the same metrics.panelKnobSize dial as
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
            // The app never lays out narrower than the layout's minimum width
            // (regular: the desktop window minimum; compact: a 640-wide
            // phone); a narrower viewport scrolls it sideways instead.
            final width = math.max(constraints.maxWidth, metrics.minAppWidth);

            final app = SizedBox(
              width: width,
              child: Column(
                children: [
                  TopBar(
                    isConsoleOpen: isConsoleOpen.value,
                    onConsoleToggle: () =>
                        isConsoleOpen.value = !isConsoleOpen.value,
                  ),
                  Expanded(
                    child: Row(
                      // Stretch so the work area fills its full height (its grey plate
                      // covers everything and the content top-aligns).
                      crossAxisAlignment: .stretch,
                      children: [
                        if (!metrics.isCompact) rail,
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
                                              padding: EdgeInsets.all(
                                                metrics.workPadding,
                                              ),
                                              // Center the work-area content vertically (grows past
                                              // the viewport → scrolls). Clone Mode moved into the
                                              // AMP editor, matching the web app.
                                              child: ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  // Never negative: the soft
                                                  // keyboard can leave the work
                                                  // area shorter than its
                                                  // padding.
                                                  minHeight: math.max(
                                                    0,
                                                    constraints.maxHeight -
                                                        2 * metrics.workPadding,
                                                  ),
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
                                                      SizedBox(
                                                        height: metrics
                                                            .chainPanelsGap,
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
                                                                    BoxConstraints(
                                                                      minHeight:
                                                                          metrics
                                                                              .minPanelHeight,
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
                                    if (kDebugMode &&
                                        isConsoleOpen.value &&
                                        !metrics.isCompact) ...[
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

            // Every wrapper here is always present: the inset padding (0
            // outside compact), the sideways scroll (inert while the app
            // fits) and the stack. Adding or removing one would remount the
            // whole app, and with it the title bar's ref in the middle of a
            // connect or an import.
            return Padding(
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: SingleChildScrollView(
                scrollDirection: .horizontal,
                physics: width > constraints.maxWidth
                    ? null
                    : const NeverScrollableScrollPhysics(),
                // The app stays at index 0 in both layouts, so the title bar
                // and the work area keep their elements when the drawer comes
                // and goes. Compact: the preset drawer over the whole app,
                // the title bar included.
                child: Stack(
                  children: [
                    app,
                    if (metrics.isCompact) Positioned.fill(child: drawer),
                  ],
                ),
              ),
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
