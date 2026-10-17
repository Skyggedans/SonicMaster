import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/preset_browser_page.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/sonic_field.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

import '../support/page_harness.dart';
import '../support/sonic_host.dart';
import '../support/view_helpers.dart';

void main() {
  group('the frame publishes the viewport\'s layout', () {
    for (final (size, isCompact) in const [
      (Size(852, 393), true), // phone landscape
      (Size(568, 320), true), // the smallest phone landscape
      (Size(393, 852), true), // phone portrait
      (Size(1280, 500), true), // a short desktop browser window
      (Size(1280, 800), false), // desktop / tablet landscape
    ]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('$label is ${isCompact ? 'compact' : 'regular'}', (
        tester,
      ) async {
        final context = await pumpSonicHost(tester, size: size);

        expect(
          SonicMetrics.of(context),
          same(isCompact ? SonicMetrics.compact : SonicMetrics.regular),
        );
      });
    }
  });

  testWidgets('a dialog route reads the same metrics as the page', (
    tester,
  ) async {
    final context = await pumpSonicHost(tester, size: const Size(852, 393));

    late SonicMetrics dialogMetrics;

    unawaited(
      showSonicDialog<void>(
        context: context,
        builder: (dialogContext) {
          dialogMetrics = SonicMetrics.of(dialogContext);

          return const SizedBox.shrink();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(dialogMetrics, same(SonicMetrics.compact));
  });

  testWidgets(
    'a native desktop window is regular even at 800x600',
    (tester) async {
      // macOS shows its window at the xib's 800x600 for a moment before
      // window_manager applies 1280x800: no compact flash at launch.
      final context = await pumpSonicHost(tester, size: const Size(800, 600));

      expect(SonicMetrics.of(context), same(SonicMetrics.regular));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets('the page itself reads compact metrics on a phone', (
    tester,
  ) async {
    await pumpPage(tester, size: const Size(852, 393), isConnected: false);

    final page = tester.element(find.byType(PresetBrowserPage));

    expect(SonicMetrics.of(page), same(SonicMetrics.compact));
  });

  testWidgets('a mode flip keeps an open dialog, its text and its focus', (
    tester,
  ) async {
    // A tablet turned to portrait while a preset name is being typed: the
    // layout flips regular -> compact under the open dialog. The Navigator and
    // its FocusScope must survive (WidgetsApp hands both to the builder).
    final context = await pumpSonicHost(tester);

    unawaited(
      showSonicDialog<void>(
        context: context,
        builder: (_) => const _NameDialog(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Lead');
    await tester.pump();

    // The FocusScope WidgetsApp puts around its Navigator: the builder's child.
    final navigatorScope = find
        .ancestor(of: find.byType(Navigator), matching: find.byType(FocusScope))
        .first;

    final scopeElement = tester.element(navigatorScope);
    final field = find.byType(EditableText);
    final state = tester.state<EditableTextState>(field);

    tester.view.physicalSize = const Size(800, 1280);
    await tester.pump();

    expect(SonicMetrics.of(tester.element(field)), same(SonicMetrics.compact));
    expect(tester.element(navigatorScope), same(scopeElement));
    expect(tester.state<EditableTextState>(field), same(state));
    expect(state.widget.focusNode.hasFocus, isTrue);
    expect(state.widget.controller.text, 'Lead');
  });

  testWidgets('the soft keyboard never flips the mode', (tester) async {
    var builds = 0;
    late SonicMetrics seen;

    // One probe instance: only the scope's notification can rebuild it.
    final probe = Builder(
      builder: (context) {
        seen = SonicMetrics.of(context);
        builds++;

        return const SizedBox.shrink();
      },
    );

    // A tablet in landscape typing behind a 400-px keyboard stays regular.
    await pumpSonicHost(tester, home: probe);
    await setKeyboard(tester, 400);

    expect(seen, same(SonicMetrics.regular));
    expect(builds, 1);

    await setKeyboard(tester, 0);
    tester.view.physicalSize = const Size(852, 393);
    await tester.pump();

    expect(seen, same(SonicMetrics.compact));
    expect(builds, 2);

    // A phone with its keyboard up stays compact.
    await setKeyboard(tester, 180);

    expect(seen, same(SonicMetrics.compact));
    expect(builds, 2);
  });
}

/// A dialog with a name field, like Save: the text lives in hook state, so a
/// remount of the route would drop it.
class _NameDialog extends HookWidget {
  const _NameDialog();

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();

    return SonicDialog(child: SonicField(controller: controller));
  }
}
