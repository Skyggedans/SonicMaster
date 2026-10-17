import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/decoded_preset_state.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/ui/chain_view.dart'; // ModuleCard, AmpBlockBorder, ChainView

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders all nine module names in one row', (tester) async {
    final fl = FontLoader('Oswald')
      ..addFont(rootBundle.load('assets/fonts/Oswald.ttf'));

    await fl.load();

    // The chain is wider than the default 800px test surface; widen it so
    // every group (including the trailing DLY/RVB singletons) is actually
    // laid out by the lazily-built ReorderableListView instead of being
    // left outside the viewport + cache extent.
    tester.view.physicalSize = const Size(2400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Seed a preset state with a default chain order and all modules on.
    const order = ['NR', 'FX1', 'DRV', 'AMP', 'IR', 'EQ', 'FX2', 'DLY', 'RVB'];
    final state = DecodedPresetState(
      isCloneMode: false,
      presetVolume: 50,
      presetBpm: 120,
      moduleStates: {for (final m in order) m: true},
      chainOrder: order,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentPresetStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ChainView())),
        ),
      ),
    );
    await tester.pump();

    for (final m in order) {
      expect(find.text(m), findsOneWidget);
    }

    // The four amp modules render inside the dashed border.
    expect(find.byType(AmpBlockBorder), findsOneWidget);
  });
}
