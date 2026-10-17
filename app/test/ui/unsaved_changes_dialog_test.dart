import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/unsaved_changes_dialog.dart';

void main() {
  // Opens the dialog, asserts it is shown, then either taps the named action
  // ([tap]) or, when [tap] is null, taps the barrier to dismiss. Returns what
  // showUnsavedChangesDialog resolved to.
  Future<bool?> openThen(WidgetTester tester, {String? tap}) async {
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showUnsavedChangesDialog(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);

    if (tap != null) {
      await tester.tap(find.text(tap));
    } else {
      await tester.tapAt(const Offset(5, 5)); // outside the dialog -> barrier
    }

    await tester.pumpAndSettle();

    return result;
  }

  testWidgets('Discard returns true', (tester) async {
    expect(await openThen(tester, tap: 'Discard'), isTrue);
  });

  testWidgets('Cancel returns false', (tester) async {
    expect(await openThen(tester, tap: 'Cancel'), isFalse);
  });

  testWidgets('barrier dismiss returns false', (tester) async {
    expect(await openThen(tester), isFalse);
  });
}
