/// The pedal's device-global settings (not per-preset).
///
/// The first five fields (volume + dB levels) plus the Mode…Power fields mirror
/// the Android app's Settings screen; they default to 0 so a partial decode never
/// fails to construct.
class GlobalSettings {
  const GlobalSettings({
    required this.globalVolume,
    required this.inputLevel,
    required this.fxRecLevel,
    required this.monitorLevel,
    required this.btRecLevel,
    this.mode = 0,
    this.reamp = 0,
    this.expFsType = 0,
    this.expFsTarget = 0,
    this.expFsTarget2 = 0,
    this.backlight = 0,
    this.eco = 0,
    this.powerConfirm = 0,
    this.battOnly = 0,
  });

  final int globalVolume; // 0..100
  final int inputLevel; // dB, -20..20
  final int fxRecLevel;
  final int monitorLevel;
  final int btRecLevel;

  final int mode; // 0 = Dry, 1 = Wet
  final int reamp; // 0/1
  final int expFsType; // 0 = EXP, 1 = SingleFS, 2 = DualFS
  final int expFsTarget; // primary target index (EXP list, or FS list / FS1)
  final int expFsTarget2; // DualFS Func 2 target index (FS list)
  final int backlight; // 0..max
  final int eco; // 0/1
  final int powerConfirm; // 0/1
  final int battOnly; // 0/1

  GlobalSettings copyWith({
    int? globalVolume,
    int? inputLevel,
    int? fxRecLevel,
    int? monitorLevel,
    int? btRecLevel,
    int? mode,
    int? reamp,
    int? expFsType,
    int? expFsTarget,
    int? expFsTarget2,
    int? backlight,
    int? eco,
    int? powerConfirm,
    int? battOnly,
  }) => GlobalSettings(
    globalVolume: globalVolume ?? this.globalVolume,
    inputLevel: inputLevel ?? this.inputLevel,
    fxRecLevel: fxRecLevel ?? this.fxRecLevel,
    monitorLevel: monitorLevel ?? this.monitorLevel,
    btRecLevel: btRecLevel ?? this.btRecLevel,
    mode: mode ?? this.mode,
    reamp: reamp ?? this.reamp,
    expFsType: expFsType ?? this.expFsType,
    expFsTarget: expFsTarget ?? this.expFsTarget,
    expFsTarget2: expFsTarget2 ?? this.expFsTarget2,
    backlight: backlight ?? this.backlight,
    eco: eco ?? this.eco,
    powerConfirm: powerConfirm ?? this.powerConfirm,
    battOnly: battOnly ?? this.battOnly,
  );
}
