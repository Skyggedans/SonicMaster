/// The pedal's device-global settings (not per-preset).
class GlobalSettings {
  const GlobalSettings({
    required this.globalVolume,
    required this.inputLevel,
    required this.fxRecLevel,
    required this.monitorLevel,
    required this.btRecLevel,
  });

  final int globalVolume; // 0..100
  final int inputLevel; // dB, -20..20
  final int fxRecLevel;
  final int monitorLevel;
  final int btRecLevel;

  GlobalSettings copyWith({
    int? globalVolume,
    int? inputLevel,
    int? fxRecLevel,
    int? monitorLevel,
    int? btRecLevel,
  }) => GlobalSettings(
    globalVolume: globalVolume ?? this.globalVolume,
    inputLevel: inputLevel ?? this.inputLevel,
    fxRecLevel: fxRecLevel ?? this.fxRecLevel,
    monitorLevel: monitorLevel ?? this.monitorLevel,
    btRecLevel: btRecLevel ?? this.btRecLevel,
  );
}
