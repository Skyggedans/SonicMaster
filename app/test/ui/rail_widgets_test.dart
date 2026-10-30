import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/theme/app_colors.dart';
import 'package:sonicmaster/ui/preset_rail.dart';

void main() {
  Widget host(Widget c) => MaterialApp(
    home: Scaffold(body: Center(child: c)),
  );

  testWidgets('PresetChip renders the slot chip + name and fires onTap', (
    tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      host(
        PresetChip(
          slot: 'P06',
          name: 'Solo Boost',
          isSelected: false,
          isEnabled: true,
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.text('P06'), findsOneWidget);
    expect(find.text('Solo Boost'), findsOneWidget);
    await tester.tap(find.text('Solo Boost'));
    expect(taps, 1);
  });

  testWidgets('a disabled PresetChip does not fire', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      host(
        PresetChip(
          slot: 'P07',
          isSelected: false,
          isEnabled: false,
          onTap: () => taps++,
        ),
      ),
    );
    await tester.tap(find.text('P07'), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('a selected PresetChip paints the orange border', (tester) async {
    await tester.pumpWidget(
      host(const PresetChip(slot: 'P06', isSelected: true, isEnabled: true)),
    );
    // The outer row container carries the selection border (the inner slot chip
    // has a fill but no border).
    final deco = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.border != null);

    expect(deco.border!.top.color, Palette.accent);
  });

  testWidgets('RailTab and RailButton render and tap', (tester) async {
    var t = 0, b = 0;

    await tester.pumpWidget(
      host(
        Column(
          children: [
            RailTab(label: 'User', isActive: true, onTap: () => t++),
            RailButton(label: 'Connect', isPrimary: true, onTap: () => b++),
          ],
        ),
      ),
    );
    expect(find.text('USER'), findsOneWidget); // uppercased
    expect(find.text('CONNECT'), findsOneWidget);
    await tester.tap(find.text('USER'));
    await tester.tap(find.text('CONNECT'));
    expect(t, 1);
    expect(b, 1);
  });
}
