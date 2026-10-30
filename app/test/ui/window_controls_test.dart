import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/ui/window_controls.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  testWidgets(
    'desktop platforms draw their own window chrome',
    (tester) async {
      expect(isDesktopWindow, isTrue);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'mobile platforms have no window chrome',
    (tester) async {
      expect(isDesktopWindow, isFalse);
    },
    variant: TargetPlatformVariant.mobile(),
  );

  // Whole-page tests rely on this: flutter test runs as android whatever the
  // host OS, so the page renders no WindowControls (no window_manager mock).
  testWidgets('flutter test runs without window chrome by default', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    expect(isDesktopWindow, isFalse);
  });

  testWidgets(
    'TopBarDragArea passes its child straight through off desktop',
    (tester) async {
      await tester.pumpWidget(const TopBarDragArea(child: SizedBox.shrink()));

      expect(find.byType(DragToMoveArea), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    },
    variant: TargetPlatformVariant.mobile(),
  );

  testWidgets(
    'TopBarDragArea makes the bar drag the window on desktop',
    (tester) async {
      await tester.pumpWidget(const TopBarDragArea(child: SizedBox.shrink()));

      expect(find.byType(DragToMoveArea), findsOneWidget);
    },
    variant: TargetPlatformVariant.desktop(),
  );
}
