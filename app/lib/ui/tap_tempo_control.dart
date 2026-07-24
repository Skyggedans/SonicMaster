import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../model/tap_tempo.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';
import 'sonic_field.dart';

/// The Delay module's tap-tempo controls, laid out as [PanelCell]s so they line
/// up with the effect's knobs in one row: a TAP push-button (its label flashes
/// orange on the beat), a recessed BPM well, a note-division dropdown, and the
/// computed-ms readout. Computes the delay Time and reports it via [onSend]
/// (clamped to [timeMin], [timeMax]). [trailing] are the module's own knob
/// cells, appended so everything flows in a single Wrap.
class TapTempoControl extends HookWidget {
  const TapTempoControl({
    super.key,
    required this.timeMin,
    required this.timeMax,
    required this.currentMs,
    required this.onSend,
    this.trailing = const [],
  });

  final int timeMin;
  final int timeMax;

  /// The delay's current Time (ms) — used to seed the BPM/readout so they agree
  /// with the TIME knob (rather than a fixed 120 bpm).
  final int currentMs;
  final void Function(int ms) onSend;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    // Seed the BPM so it agrees with the delay Time on first paint (multiplier
    // starts at the default 1/4 division).
    final bpm = useState(currentMs <= 0 ? 120.0 : clampBpm(60000 / currentMs));

    final multiplier = useState(1.0);
    final taps = useMemoized(() => <int>[]);
    final resetTimer = useRef<Timer?>(null);
    final beatTimer = useRef<Timer?>(null);
    final isBeatOn = useState(false);
    // The last ms WE pushed — used to ignore its echo on the next Time change.
    final lastSent = useRef<int?>(null);
    final isMounted = useRef(true);
    final bpmCtl = useTextEditingController(text: bpm.value.toStringAsFixed(1));

    int sentMs() =>
        delayMs(bpm.value, multiplier.value).clamp(timeMin, timeMax).round();

    void send() {
      final ms = sentMs();

      lastSent.value = ms;
      onSend(ms);
    }

    // Back-compute the BPM that yields [ms] at the current division, so the BPM
    // well and computed-ms readout agree with the actual delay Time.
    void seedFromMs(int ms) {
      if (ms <= 0) return;

      bpm.value = clampBpm(60000 * multiplier.value / ms);
      bpmCtl.text = bpm.value.toStringAsFixed(1);
    }

    // Blink the TAP label orange on every beat at the current BPM (a metronome
    // indicator, like the reference web app).
    void restartBeat() {
      beatTimer.value?.cancel();

      final period = (60000 / bpm.value).round().clamp(60, 2000);

      beatTimer.value = Timer.periodic(Duration(milliseconds: period), (_) {
        if (!isMounted.value) return;

        isBeatOn.value = true;
        Timer(
          Duration(milliseconds: (period * 0.28).round().clamp(40, 140)),
          () {
            if (isMounted.value) isBeatOn.value = false;
          },
        );
      });
    }

    void submitBpm(String s) {
      final v = double.tryParse(s);

      if (v == null) return;

      bpm.value = clampBpm(v);
      bpmCtl.text = bpm.value.toStringAsFixed(1);
      restartBeat();
      send();
    }

    void tap() {
      final now = DateTime.now().millisecondsSinceEpoch;

      taps.add(now);

      if (taps.length > 4) taps.removeAt(0);

      resetTimer.value?.cancel();
      resetTimer.value = Timer(const Duration(seconds: 2), taps.clear);

      final tapped = bpmFromTaps(taps);

      if (tapped != null) {
        bpm.value = clampBpm(tapped);
        bpmCtl.text = bpm.value.toStringAsFixed(1);
        send();
        restartBeat();
      }
    }

    // Cancel the timers (and flag unmount) when the widget goes away.
    useEffect(() {
      return () {
        isMounted.value = false;
        resetTimer.value?.cancel();
        beatTimer.value?.cancel();
      };
    }, const []);

    // Reflect the delay Time on mount and on external changes (preset load /
    // TIME-knob drag) — but not the echo of a value we ourselves just sent.
    useEffect(() {
      if (currentMs != lastSent.value) {
        seedFromMs(currentMs);
        restartBeat();
      }

      return null;
    }, [currentMs]);

    final raw = delayMs(bpm.value, multiplier.value);
    final outOfRange = raw > timeMax;
    final shown = raw.clamp(timeMin, timeMax).round();

    return Wrap(
      alignment: .center,
      spacing: 4,
      runSpacing: 4,
      children: [
        // TAP — push button; its label flashes orange on the beat.
        PanelCell(
          control: SonicButton(
            label: 'TAP',
            height: 44,
            minWidth: 92,
            isAccent: isBeatOn.value,
            onPressed: tap,
          ),
        ),
        // BPM — recessed well with an editable value, label below.
        PanelCell(
          label: 'BPM',
          control: SonicRecess(
            radius: 10,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: SizedBox(
              width: 60,
              child: SonicField(
                controller: bpmCtl,
                textAlign: .center,
                style: AppText.bpm,
                isRecessed: false,
                padding: EdgeInsets.zero,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onSubmitted: submitBpm,
              ),
            ),
          ),
        ),
        // Note division — dropdown (was a segmented bar).
        PanelCell(
          label: 'Div',
          control: SonicDropdown<double>(
            value: multiplier.value,
            width: 92,
            items: [
              for (final (label, mult) in noteDivisions)
                (value: mult, label: label),
            ],
            onChanged: (m) {
              multiplier.value = m;
              send();
            },
          ),
        ),
        // Computed delay time — plain Oswald text, centered with the knobs.
        PanelCell(
          control: Text(
            '$shown ms',
            style: AppText.bpmDisplay.copyWith(
              color: outOfRange ? Palette.error : Palette.textPrimary,
            ),
          ),
        ),
        ...trailing,
      ],
    );
  }
}
