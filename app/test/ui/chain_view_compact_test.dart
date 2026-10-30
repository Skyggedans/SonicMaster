import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/model/decoded_preset_state.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/device_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/chain_view.dart';
import 'package:sonicmaster/ui/led_button.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

import '../support/page_harness.dart';
import '../support/silent_transport.dart';
import '../support/sonic_host.dart';
import '../support/test_assets.dart';
import '../support/view_helpers.dart';

/// The compact signal chain: one row whatever the phone width, cards from 96
/// down to 54 px, slim card internals, and the FS badge on the card corner.
/// Regular keeps its 96-px cards and wraps exactly as before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final assets = loadTestDataAssets();

  group('card width', () {
    double compactCard(double availableWidth) => chainCardWidth(
      SonicMetrics.compact,
      availableWidth: availableWidth,
      cardCount: 9,
      hasAmpBlock: true,
    );

    test('compact keeps nine cards on one row, down to the 54 floor', () {
      expect(compactCard(836), 77); // 852-wide phone
      expect(compactCard(764), 69); // 780
      expect(compactCard(624), 54); // 640, the compact minimum
      expect(compactCard(400), 54); // below it: clamped, the Wrap breaks rows
      expect(compactCard(1600), 96); // a wide but short browser window
    });

    test('regular cards are always 96', () {
      for (final availableWidth in const [300.0, 692.0, 2400.0]) {
        expect(
          chainCardWidth(
            SonicMetrics.regular,
            availableWidth: availableWidth,
            cardCount: 9,
            hasAmpBlock: true,
          ),
          96,
        );
      }
    });

    test('one row is cards + connectors + amp-block padding', () {
      expect(chainRowWidth(SonicMetrics.regular, cardWidth: 96), 1076);
      expect(chainRowWidth(SonicMetrics.compact, cardWidth: 54), 622);
      expect(
        chainRowWidth(
          SonicMetrics.compact,
          cardWidth: 54,
          cardCount: 5,
          hasAmpBlock: false,
        ),
        5 * 54 + 4 * 16,
      );
    });

    test('an empty chain or an unbounded width gets the widest card', () {
      expect(
        chainCardWidth(
          SonicMetrics.compact,
          availableWidth: 624,
          cardCount: 0,
          hasAmpBlock: false,
        ),
        96,
      );
      expect(compactCard(double.infinity), 96);
    });
  });

  /// Pumps the chain into [width] of the real app shell: 852x393 gives the
  /// compact metrics, 1280x800 the regular ones. NR is the selected module.
  Future<ProviderContainer> pumpChain(
    WidgetTester tester, {
    required double width,
    bool isCompact = true,
    DecodedPresetState state = loadedPresetState,
  }) async {
    final context = await pumpSonicHost(
      tester,
      size: isCompact ? const Size(852, 393) : const Size(1280, 800),
      overrides: [
        dataAssetsProvider.overrideWith((_) => assets),
        deviceServiceProvider.overrideWithValue(
          DeviceService(SilentTransport()),
        ),
        currentPresetStateProvider.overrideWith((_) => state),
      ],
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: const SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: ChainView(),
            ),
          ),
        ),
      ),
    );

    final container = ProviderScope.containerOf(context);

    await container.read(dataAssetsProvider.future);
    await tester.pump();

    return container;
  }

  // Top edges of all nine cards: one row means they (nearly) coincide.
  List<double> cardTops(WidgetTester tester) => find
      .byType(ModuleCard)
      .evaluate()
      .map((element) => tester.getTopLeft(find.byWidget(element.widget)).dy)
      .toList();

  double spread(List<double> values) =>
      values.reduce((a, b) => a > b ? a : b) -
      values.reduce((a, b) => a < b ? a : b);

  for (final (width, card) in const [
    (836.0, 77.0),
    (764.0, 69.0),
    (624.0, 54.0),
  ]) {
    testWidgets(
      'compact ${width.toInt()}: one row of ${card.toInt()}-px cards',
      (tester) async {
        await pumpChain(tester, width: width);

        expectNoOverflow(tester);
        // The cards of the amp block sit 4 px lower (its padding); a second row
        // would be ~110 px lower.
        expect(spread(cardTops(tester)), lessThanOrEqualTo(4));
        expect(
          find.byType(ModuleCard).evaluate().map((e) => e.size!.width),
          everyElement(card),
        );
      },
    );
  }

  testWidgets('regular 692: 96-px cards wrap as before', (tester) async {
    await pumpChain(tester, width: 692, isCompact: false);

    expect(
      find.byType(ModuleCard).evaluate().map((e) => e.size!.width),
      everyElement(96),
    );
    expect(spread(cardTops(tester)), greaterThan(100));
  });

  // The card height is derived, never a literal: Oswald lines are 1.482 em
  // laid out on whole pixels (12-px name 18, 10-px effect 15), so the compact
  // card is 101 and the regular one 141 (2 more when selected).
  for (final isCompact in const [true, false]) {
    final metrics = isCompact ? SonicMetrics.compact : SonicMetrics.regular;
    final mode = isCompact ? 'compact' : 'regular';

    testWidgets('$mode: card internals follow the metrics', (tester) async {
      await pumpChain(
        tester,
        width: isCompact ? 836 : 1200,
        isCompact: isCompact,
      );

      final fx1 = find.byType(ModuleCard).at(1); // unselected: 1-px border
      final name = tester.getSize(
        find.descendant(of: fx1, matching: find.text('FX1')),
      );

      final effect = tester.getSize(
        find.descendant(of: fx1, matching: find.text('—')),
      );

      final height =
          2 +
          metrics.chainCardPadding.vertical +
          10 + // DragGrip: two rows of 5-px dots
          metrics.chainGripGap +
          metrics.chainIconSize +
          metrics.chainIconGap +
          name.height +
          effect.height +
          metrics.chainLedGap +
          metrics.chainLedSize.height;

      expect(tester.getSize(fx1).height, closeTo(height, 0.01));
      expect(
        tester.getSize(
          find.descendant(of: fx1, matching: find.byType(LedButton)),
        ),
        metrics.chainLedSize,
      );
      expect(
        tester.getSize(find.byType(ChainConnector).first).width,
        metrics.chainConnectorWidth,
      );
    });
  }

  for (final isCompact in const [true, false]) {
    final mode = isCompact ? 'compact' : 'regular';

    testWidgets(
      '$mode: the FS badge sits ${isCompact ? 'over' : 'below'} the card corner',
      (tester) async {
        await pumpChain(
          tester,
          width: isCompact ? 836 : 1200,
          isCompact: isCompact,
          // FX1 (module 1) on FS1.
          state: loadedPresetState.withFootswitchMasks(
            fs1Mask: 1 << 1,
            fs2Mask: 0,
          ),
        );

        // The badge chip: the nearest Container around its label.
        final badge = tester.getRect(
          find
              .ancestor(of: find.text('FS1'), matching: find.byType(Container))
              .first,
        );

        final card = tester.getRect(find.byType(ModuleCard).at(1));

        expect(badge.top, closeTo(card.top + (isCompact ? -6 : 20), 0.01));
        expect(badge.right, closeTo(card.right + 4, 0.01));
      },
    );
  }

  testWidgets('compact 624: dragging NR onto DLY still reorders the chain', (
    tester,
  ) async {
    final container = await pumpChain(tester, width: 624);
    final from = tester.getCenter(find.text('NR'));
    final to = tester.getCenter(find.text('DLY'));
    final gesture = await tester.startGesture(from);

    await gesture.moveBy(const Offset(24, 0)); // past the slop, sideways
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(container.read(currentPresetStateProvider)!.chainOrder, [
      'FX1',
      'DRV',
      'AMP',
      'IR',
      'EQ',
      'FX2',
      'NR',
      'DLY',
      'RVB',
    ]);
  });
}
