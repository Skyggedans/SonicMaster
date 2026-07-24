import 'command_library.dart';

/// A reference to one of the pedal's 100 presets (50 User + 50 Factory).
class PresetRef {
  const PresetRef(this.bank, this.number);

  final PresetBank bank;
  final int number; // 1..50

  String get label =>
      '${bank == .user ? 'P' : 'F'}${number.toString().padLeft(2, '0')}';

  static List<PresetRef> all() => [
    for (final bank in PresetBank.values)
      ...List.generate(50, (i) => PresetRef(bank, i + 1)),
  ];

  @override
  bool operator ==(Object other) =>
      other is PresetRef && other.bank == bank && other.number == number;

  @override
  int get hashCode => Object.hash(bank, number);
}
