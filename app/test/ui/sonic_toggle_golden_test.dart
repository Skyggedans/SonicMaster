import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';

// Renders SonicToggle (off + on) so its look can be eyeballed via the golden
// PNG without a device. Not an assertion of correctness — regenerate with
// `flutter test --update-goldens` when the toggle style changes intentionally.
void main() {
  testWidgets('SonicToggle golden (off + on)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF1C1713),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: .min,
                children: [
                  Row(
                    mainAxisSize: .min,
                    children: [
                      SonicToggle(value: false, onChanged: (_) {}, height: 40),
                      const SizedBox(width: 40),
                      SonicToggle(value: true, onChanged: (_) {}, height: 40),
                    ],
                  ),
                  const SizedBox(height: 40),
                  // 2x native so the knob's convex shading is clearly visible.
                  Row(
                    mainAxisSize: .min,
                    children: [
                      SonicToggle(value: false, onChanged: (_) {}, height: 92),
                      const SizedBox(width: 40),
                      SonicToggle(value: true, onChanged: (_) {}, height: 92),
                    ],
                  ),
                  const SizedBox(height: 40),
                  // Push buttons (raised, at rest) — Cancel + accent Discard.
                  Row(
                    mainAxisSize: .min,
                    children: [
                      SonicButton(label: 'Cancel', onPressed: () {}),
                      const SizedBox(width: 16),
                      SonicButton(
                        label: 'Discard',
                        isAccent: true,
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  // Recessed description well (like the inactive toggle body).
                  const SizedBox(
                    width: 560,
                    child: SonicRecess(
                      radius: 10,
                      padding: EdgeInsets.fromLTRB(14, 12, 16, 12),
                      child: Text(
                        'Based on famous Xotic® EP Booster* pedal.',
                        style: TextStyle(
                          color: Color(0xFFAAAAAA),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Padding).first,
      matchesGoldenFile('goldens/sonic_toggle.png'),
    );
  });
}
