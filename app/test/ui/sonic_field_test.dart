import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/sonic_field.dart';

void main() {
  group('numericKeyboardType', () {
    test('an unsigned value gets the decimal number pad everywhere', () {
      const pad = TextInputType.numberWithOptions(decimal: true);

      expect(numericKeyboardType(isSigned: false, isWeb: false), pad);
      expect(numericKeyboardType(isSigned: false, isWeb: true), pad);
    });

    test('a signed value gets a signed number pad natively', () {
      expect(
        numericKeyboardType(isSigned: true, isWeb: false),
        const TextInputType.numberWithOptions(signed: true, decimal: true),
      );
    });

    test('a signed value gets the full keyboard on the web', () {
      // The web engine drops `signed`; the text keyboard always has '-'.
      expect(
        numericKeyboardType(isSigned: true, isWeb: true),
        TextInputType.text,
      );
    });
  });

  testWidgets('the field hands its entry options to the EditableText', (
    tester,
  ) async {
    final controller = TextEditingController(text: '12');

    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: SonicField(
          controller: controller,
          selectAllOnFocus: true,
          autocorrect: false,
          enableSuggestions: false,
        ),
      ),
    );

    final editable = tester.widget<EditableText>(find.byType(EditableText));

    expect(editable.selectAllOnFocus, isTrue);
    expect(editable.autocorrect, isFalse);
    expect(editable.enableSuggestions, isFalse);
  });

  testWidgets('by default the field keeps the SDK\'s entry behaviour', (
    tester,
  ) async {
    final controller = TextEditingController();

    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: SonicField(controller: controller),
      ),
    );

    final editable = tester.widget<EditableText>(find.byType(EditableText));

    expect(editable.selectAllOnFocus, isFalse); // the android default
    expect(editable.autocorrect, isTrue);
    expect(editable.enableSuggestions, isTrue);
  });
}
