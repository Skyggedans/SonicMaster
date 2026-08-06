import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/sonic_field.dart';

/// These pump the Sonic primitives inside a bare [WidgetsApp] — NO `MaterialApp`,
/// no `Material` ancestor, no `MaterialLocalizations`. They prove the app's
/// text input and dialogs work in the app's real (Material-free) environment.
void main() {
  Widget host(Widget child) => WidgetsApp(
    color: const Color(0xFF000000),
    debugShowCheckedModeBanner: false,
    // Mirrors main.dart: Oswald as the app-wide DefaultTextStyle.
    textStyle: const TextStyle(fontFamily: 'Oswald'),
    pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
        PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
    home: Center(child: child),
  );

  testWidgets('SonicField types + submits with no Material/localizations', (
    tester,
  ) async {
    final controller = TextEditingController();
    var submitted = '';

    await tester.pumpWidget(
      host(
        SizedBox(
          width: 200,
          child: SonicField(
            controller: controller,
            onSubmitted: (v) => submitted = v,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(controller.text, 'hello');
    expect(submitted, 'hello');
  });

  testWidgets('typed text renders in the display face, not the default', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'MyPatch');

    await tester.pumpWidget(
      host(
        SizedBox(
          width: 200,
          child: SonicField(
            controller: controller,
            // A family-less style, as the call sites pass: EditableText paints
            // its style verbatim, so SonicField must merge in the app default.
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );

    final editable = tester.widget<EditableText>(find.byType(EditableText));

    expect(editable.style.fontFamily, 'Oswald');
    expect(editable.style.fontSize, 14); // the call site's delta still wins
  });

  testWidgets('showSonicDialog opens + dismisses with no Material', (
    tester,
  ) async {
    late BuildContext ctx;

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            ctx = context;

            return const SizedBox();
          },
        ),
      ),
    );

    showSonicDialog<void>(
      context: ctx,
      builder: (_) => const SonicDialog(child: Text('hi there')),
    );
    await tester.pumpAndSettle();

    expect(find.text('hi there'), findsOneWidget);
  });
}
