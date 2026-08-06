// Placeholder smoke test. The real UI (Plan 5b) is device-backed and verified
// live; it will get proper widget tests with a faked DeviceService there.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a MaterialApp builds', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
