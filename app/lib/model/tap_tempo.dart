/// Note-division options for tap tempo, in display order: (label, multiplier).
/// '1/4' (multiplier 1.0) is the default.
const noteDivisions = <(String, double)>[
  ('1/8', 0.5),
  ('1/8·', 0.75),
  ('1/4', 1.0),
  ('1/2', 2.0),
];

/// Clamps [bpm] to [20, 300] and rounds to the nearest 0.5.
double clampBpm(double bpm) => (bpm.clamp(20.0, 300.0) * 2).round() / 2;

/// Delay time in ms for [bpm] at note [multiplier]:
/// `(60000 / clampBpm(bpm)) * multiplier`, rounded. NOT clamped to any Time
/// range — the caller clamps to [Time.min, Time.max] and uses this raw value
/// for the out-of-range check.
int delayMs(double bpm, double multiplier) =>
    ((60000 / clampBpm(bpm)) * multiplier).round();

/// BPM from tap timestamps (ms): `60000 / mean(consecutive intervals)`.
/// Null if fewer than 2 taps, or the mean interval is <= 0 or >= 3000 ms.
double? bpmFromTaps(List<int> tapTimestampsMs) {
  if (tapTimestampsMs.length < 2) return null;

  final sum = tapTimestampsMs.indexed
      .skip(1)
      .fold(0, (acc, e) => acc + e.$2 - tapTimestampsMs[e.$1 - 1]);

  final mean = sum / (tapTimestampsMs.length - 1);

  if (mean <= 0 || mean >= 3000) return null;

  return 60000 / mean;
}
