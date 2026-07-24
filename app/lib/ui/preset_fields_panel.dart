import 'package:flutter/widgets.dart';

import '../state/preset_providers.dart';
import 'knob_control.dart';
import 'sonic_controls.dart';

/// Fixed panel width — enough for Preset Vol and BPM side by side. It must NOT
/// depend on the stacked/side-by-side choice: the effect editor beside it is an
/// Expanded, so a width that changed with the layout would change the editor's
/// width, flip whether its knobs wrap, flip `stacked`, and oscillate every frame
/// (visible flicker). Holding the width constant breaks that feedback loop; when
/// stacked, the two knobs simply centre in this width. Sized from the measured
/// side-by-side width (~351 at the default text scale) with a small margin.
const double _presetPanelWidth = 360;

/// The preset-level panel to the left of the effect editor: Preset Vol and
/// Preset BPM. [topSpacer] lines the first knob up with the module's knob row.
///
/// Layout mirrors the module knobs: [stacked] (the module's Wrap spilled onto a
/// second line) puts BPM below Preset Vol; otherwise they sit side by side on the
/// single row. [patchKnobKey] lets the parent measure one knob's height to
/// decide [stacked].
class PresetFieldsPanel extends StatelessWidget {
  const PresetFieldsPanel({
    super.key,
    required this.presetVolume,
    required this.presetBpm,
    required this.isLoading,
    required this.topSpacer,
    required this.stacked,
    required this.patchKnobKey,
    required this.onVolume,
    required this.onBpm,
  });

  final int presetVolume;
  final int presetBpm;
  final bool isLoading;
  final double topSpacer;
  final bool stacked;
  final Key patchKnobKey;
  final ValueChanged<int> onVolume;
  final ValueChanged<int> onBpm;

  @override
  Widget build(BuildContext context) {
    final patchVol = KnobControl(
      key: patchKnobKey,
      value: presetVolume,
      min: 0,
      max: 100,
      step: 1,
      label: 'Preset Vol',
      isEnabled: !isLoading,
      onChanged: (v) => onVolume(v.round()),
    );

    final bpm = KnobControl(
      value: presetBpm,
      min: presetBpmMin,
      max: presetBpmMax,
      step: 1,
      label: 'BPM',
      isEnabled: !isLoading,
      onChanged: (v) => onBpm(v.round()),
    );

    return SizedBox(
      width: _presetPanelWidth,
      child: SonicSurface(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: .min,
          children: [
            SizedBox(height: topSpacer),
            if (stacked) ...[
              patchVol,
              bpm,
            ] else
              Row(
                mainAxisSize: .min,
                mainAxisAlignment: .center,
                children: [patchVol, const SizedBox(width: 8), bpm],
              ),
          ],
        ),
      ),
    );
  }
}
