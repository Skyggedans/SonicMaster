import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/chain_view.dart';
import 'package:sonicmaster/ui/led_button.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('renders name + effect and fires onSelect on body tap', (
    tester,
  ) async {
    var selects = 0;

    await tester.pumpWidget(
      host(
        ModuleCard(
          iconId: 0,
          name: 'NR',
          effect: 'Gate',
          isOn: true,
          isSelected: false,
          isEnabled: true,
          onSelect: () => selects++,
          onToggle: () {},
        ),
      ),
    );
    expect(find.text('NR'), findsOneWidget);
    expect(find.text('Gate'), findsOneWidget);
    await tester.tap(find.text('NR'));
    expect(selects, 1);
  });

  testWidgets('the LedButton reflects on and fires onToggle', (tester) async {
    var toggles = 0;

    await tester.pumpWidget(
      host(
        ModuleCard(
          iconId: 1,
          name: 'FX1',
          effect: 'Comp',
          isOn: true,
          isSelected: false,
          isEnabled: true,
          onSelect: () {},
          onToggle: () => toggles++,
        ),
      ),
    );
    final led = tester.widget<LedButton>(find.byType(LedButton));

    expect(led.isOn, isTrue);
    await tester.tap(find.byType(LedButton));
    expect(toggles, 1);
  });

  testWidgets('off card dims the display but not the LedButton', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ModuleCard(
          iconId: 2,
          name: 'DRV',
          effect: 'TS808',
          isOn: false,
          isSelected: false,
          isEnabled: true,
          onSelect: () {},
          onToggle: () {},
        ),
      ),
    );
    // The name sits under a 0.4 Opacity; the LedButton does not.
    final dimmed = tester.widget<Opacity>(
      find.ancestor(of: find.text('DRV'), matching: find.byType(Opacity)),
    );

    expect(dimmed.opacity, 0.4);
    expect(
      find.ancestor(of: find.byType(LedButton), matching: find.byType(Opacity)),
      findsNothing,
    );
  });

  testWidgets('disabled gives the LedButton a null onTap', (tester) async {
    await tester.pumpWidget(
      host(
        const ModuleCard(
          iconId: 3,
          name: 'AMP',
          effect: null,
          isOn: true,
          isSelected: false,
          isEnabled: false,
        ),
      ),
    );
    expect(tester.widget<LedButton>(find.byType(LedButton)).onTap, isNull);
  });
}
