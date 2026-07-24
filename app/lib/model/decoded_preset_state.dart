/// The decoded contents of a preset-state dump.
class DecodedPresetState {
  const DecodedPresetState({
    required this.isCloneMode,
    required this.presetVolume,
    required this.presetBpm,
    required this.moduleStates,
    required this.chainOrder,
    this.footswitchFs1Mask = 0,
    this.footswitchFs2Mask = 0,
  });

  final bool isCloneMode;
  final int presetVolume;

  /// Tempo the preset's Sync-capable effects follow, in BPM. Hardware range
  /// 40–260; there is no global tempo — this is per-preset.
  final int presetBpm;
  final Map<String, bool> moduleStates; // module name -> on
  final List<String> chainOrder; // module names, signal order

  /// Bitmask of the modules assigned to hardware footswitch FS1 / FS2 — bit `M`
  /// set means module id `M` (per `modules.json`) reacts to that switch. The
  /// hardware allows several modules per switch (factory presets group e.g. DLY
  /// + RVB); the editor UI restricts *new* assignments to one owner per switch.
  final int footswitchFs1Mask;
  final int footswitchFs2Mask;

  DecodedPresetState copyWith({
    bool? isCloneMode,
    int? presetVolume,
    int? presetBpm,
    Map<String, bool>? moduleStates,
    List<String>? chainOrder,
  }) => DecodedPresetState(
    isCloneMode: isCloneMode ?? this.isCloneMode,
    presetVolume: presetVolume ?? this.presetVolume,
    presetBpm: presetBpm ?? this.presetBpm,
    moduleStates: moduleStates ?? this.moduleStates,
    chainOrder: chainOrder ?? this.chainOrder,
    footswitchFs1Mask: footswitchFs1Mask,
    footswitchFs2Mask: footswitchFs2Mask,
  );

  /// Replaces both footswitch masks at once (a dedicated setter because
  /// [copyWith]'s `?? this` idiom can't distinguish a cleared 0 mask).
  DecodedPresetState withFootswitchMasks({
    required int fs1Mask,
    required int fs2Mask,
  }) => DecodedPresetState(
    isCloneMode: isCloneMode,
    presetVolume: presetVolume,
    presetBpm: presetBpm,
    moduleStates: moduleStates,
    chainOrder: chainOrder,
    footswitchFs1Mask: fs1Mask,
    footswitchFs2Mask: fs2Mask,
  );
}
