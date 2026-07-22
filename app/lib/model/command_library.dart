/// Which bank a preset lives in.
enum PresetBank { user, factory }

/// Pre-baked SysEx command frames captured from the device, keyed for lookup.
class CommandLibrary {
  const CommandLibrary({
    required this.moduleStates,
    required this.ampFactory,
    required this.ampClone,
    required this.effectTypes,
    required this.parameters,
    required this.chainOrderCommands,
    required this.globalCommands,
    required this.presetCommands,
  });

  /// moduleId -> {'on': hex, 'off': hex}
  final Map<int, Map<String, String>> moduleStates;
  final String ampFactory;
  final String ampClone;

  /// moduleId -> (effectId -> hex frame)
  final Map<int, Map<int, String>> effectTypes;

  /// moduleId -> algId -> value-key string -> hex frame.
  /// Value keys are raw strings ("0", "-50", "0.1"); see the reference note.
  final Map<int, Map<int, Map<String, String>>> parameters;

  /// order key ("NR-FX1-...-EQ") -> hex frame
  final Map<String, String> chainOrderCommands;

  /// setting name -> value -> hex frame
  final Map<String, Map<int, String>> globalCommands;

  /// bank ("user"/"factory") -> preset key ("P01".."F50") -> hex frame
  final Map<String, Map<String, String>> presetCommands;

  String? moduleOn(int moduleId) => moduleStates[moduleId]?['on'];
  String? moduleOff(int moduleId) => moduleStates[moduleId]?['off'];
  String? effectType(int moduleId, int effectId) =>
      effectTypes[moduleId]?[effectId];
  List<int> effectIdsFor(int moduleId) =>
      // Fresh (modifiable) fallback: sorting a `const []` throws "Cannot modify
      // an unmodifiable list" for a module with no effects (NR / Clone). No UI
      // path reaches that today, but it's a latent trap for any caller.
      (effectTypes[moduleId]?.keys.toList() ?? <int>[])..sort();

  String? parameterCommand(int moduleId, int algId, String value) =>
      parameters[moduleId]?[algId]?[value];

  String? chainOrderCommand(String orderKey) => chainOrderCommands[orderKey];

  String? globalCommand(String name, int value) => globalCommands[name]?[value];

  String? presetSelect(PresetBank bank, int number) {
    final prefix = bank == .user ? 'P' : 'F';
    final table = presetCommands[bank == .user ? 'user' : 'factory'];

    return table?['$prefix${number.toString().padLeft(2, '0')}'];
  }

  factory CommandLibrary.fromJson(Map<String, dynamic> json) {
    final states = <int, Map<String, String>>{};

    (json['moduleStates'] as Map<String, dynamic>).forEach((k, v) {
      final m = v as Map<String, dynamic>;

      states[int.parse(k)] = {
        'on': m['on'] as String,
        'off': m['off'] as String,
      };
    });

    final amp = json['ampModes'] as Map<String, dynamic>;

    final effects = <int, Map<int, String>>{};

    (json['effectTypes'] as Map<String, dynamic>).forEach((moduleId, byEffect) {
      effects[int.parse(moduleId)] = {
        for (final e in (byEffect as Map<String, dynamic>).entries)
          int.parse(e.key): e.value as String,
      };
    });

    final params = <int, Map<int, Map<String, String>>>{};

    (json['parameters'] as Map<String, dynamic>).forEach((moduleId, byAlg) {
      final algMap = <int, Map<String, String>>{};

      (byAlg as Map<String, dynamic>).forEach((algId, byValue) {
        algMap[int.parse(algId)] = {
          for (final e in (byValue as Map<String, dynamic>).entries)
            e.key: e.value as String,
        };
      });

      params[int.parse(moduleId)] = algMap;
    });

    final chain = {
      for (final e
          in (json['chainOrderCommands'] as Map<String, dynamic>).entries)
        e.key: e.value as String,
    };

    final global = <String, Map<int, String>>{};

    (json['globalCommands'] as Map<String, dynamic>).forEach((name, byValue) {
      global[name] = {
        for (final e in (byValue as Map<String, dynamic>).entries)
          int.parse(e.key): e.value as String,
      };
    });

    final presets = <String, Map<String, String>>{};

    (json['presetCommands'] as Map<String, dynamic>).forEach((bank, byKey) {
      presets[bank] = {
        for (final e in (byKey as Map<String, dynamic>).entries)
          e.key: e.value as String,
      };
    });

    return CommandLibrary(
      moduleStates: states,
      ampFactory: amp['factory'] as String,
      ampClone: amp['clone'] as String,
      effectTypes: effects,
      parameters: params,
      chainOrderCommands: chain,
      globalCommands: global,
      presetCommands: presets,
    );
  }
}
