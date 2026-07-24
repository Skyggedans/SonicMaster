/// Control type for an effect parameter, from the legacy `widgetType` field.
enum WidgetType {
  knob, // 0: continuous value (min/max/step)
  toggle, // 1: on/off (0/1)
  select, // 2: enumerated options
  eqBand; // 3: bipolar EQ frequency band (min/max/step); a slider like knob

  static WidgetType fromCode(int code) {
    switch (code) {
      case 0:
        return .knob;
      case 1:
        return .toggle;
      case 2:
        return .select;
      case 3:
        return .eqBand;
      default:
        throw ArgumentError('unknown widgetType: $code');
    }
  }
}
