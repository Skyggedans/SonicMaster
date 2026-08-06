import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/chain_view.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('ChainConnector shows a chevron icon', (tester) async {
    await tester.pumpWidget(host(const ChainConnector()));
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('AmpBlockBorder wraps its child without error', (tester) async {
    await tester.pumpWidget(host(const AmpBlockBorder(child: Text('block'))));
    expect(find.text('block'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
