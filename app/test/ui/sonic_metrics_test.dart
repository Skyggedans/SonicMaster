import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

void main() {
  group('isCompactViewport (D1: width < 960 or height < 600)', () {
    for (final (size, isCompact) in const [
      (Size(1280, 800), false), // desktop default window
      (Size(960, 640), false), // desktop window minimum
      (Size(960, 600), false), // both edges exactly on the threshold
      (Size(1024, 768), false), // tablet landscape
      (Size(959, 800), true), // one px too narrow
      (Size(960, 599), true), // one px too short
      (Size(1280, 500), true), // a short desktop browser window
      (Size(852, 393), true), // phone landscape
      (Size(568, 320), true), // the smallest phone landscape
      (Size(393, 852), true), // phone portrait
      (Size(800, 1280), true), // tablet portrait (D6a: compact, no prompt)
    ]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      test('$label is ${isCompact ? 'compact' : 'regular'}', () {
        expect(isCompactViewport(size), isCompact);
      });
    }
  });

  test('forSize hands out the two canonical instances', () {
    expect(
      SonicMetrics.forSize(const Size(1280, 800)),
      same(SonicMetrics.regular),
    );
    expect(
      SonicMetrics.forSize(const Size(959, 800)),
      same(SonicMetrics.compact),
    );
    expect(
      SonicMetrics.forSize(const Size(960, 599)),
      same(SonicMetrics.compact),
    );
  });

  test('regular tokens equal the literals they replace', () {
    const metrics = SonicMetrics.regular;

    expect(metrics.isCompact, isFalse);
    expect(metrics.topBarHeight, 60);
    expect(metrics.minAppWidth, 960);
    expect(metrics.topBarIconPadding, const EdgeInsets.all(8));
  });

  test('compact tokens', () {
    const metrics = SonicMetrics.compact;

    expect(metrics.isCompact, isTrue);
    expect(metrics.topBarHeight, 48);
    expect(metrics.minAppWidth, 640);
    expect(
      metrics.topBarIconPadding,
      const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    );
  });

  test(
    'a 22-px title-bar glyph plus its padding fits the bar in both modes',
    () {
      const glyph = 22.0;

      for (final metrics in const [
        SonicMetrics.regular,
        SonicMetrics.compact,
      ]) {
        final target = Size(
          glyph + metrics.topBarIconPadding.horizontal,
          glyph + metrics.topBarIconPadding.vertical,
        );

        expect(target.width, 38);
        expect(target.height, lessThanOrEqualTo(metrics.topBarHeight));
      }

      expect(glyph + SonicMetrics.compact.topBarIconPadding.vertical, 46);
    },
  );

  test('motion constants are the inlined SonicToggle values', () {
    expect(sonicMotionDuration, const Duration(milliseconds: 160));
    expect(
      [
        sonicMotionCurve.a,
        sonicMotionCurve.b,
        sonicMotionCurve.c,
        sonicMotionCurve.d,
      ],
      [0.4, 0.15, 0.3, 1],
    );
  });

  testWidgets('of() falls back to regular without a scope', (tester) async {
    late SonicMetrics seen;

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = SonicMetrics.of(context);

          return const SizedBox.shrink();
        },
      ),
    );

    expect(seen, same(SonicMetrics.regular));
  });

  testWidgets('of() reads the nearest scope', (tester) async {
    late SonicMetrics seen;

    await tester.pumpWidget(
      SonicMetricsScope(
        metrics: SonicMetrics.regular,
        child: SonicMetricsScope(
          metrics: SonicMetrics.compact,
          child: Builder(
            builder: (context) {
              seen = SonicMetrics.of(context);

              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(seen, same(SonicMetrics.compact));
  });

  testWidgets('the scope notifies its dependents only when the set changes', (
    tester,
  ) async {
    var builds = 0;
    late SonicMetrics seen;

    // One probe instance for every pump: Flutter skips rebuilding an identical
    // widget, so any later build is the scope's notification.
    final probe = Builder(
      builder: (context) {
        seen = SonicMetrics.of(context);
        builds++;

        return const SizedBox.shrink();
      },
    );

    await tester.pumpWidget(
      SonicMetricsScope(metrics: SonicMetrics.compact, child: probe),
    );
    await tester.pumpWidget(
      SonicMetricsScope(metrics: SonicMetrics.compact, child: probe),
    );

    expect(builds, 1);

    await tester.pumpWidget(
      SonicMetricsScope(metrics: SonicMetrics.regular, child: probe),
    );

    expect(builds, 2);
    expect(seen, same(SonicMetrics.regular));
  });
}
