import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart'; // Icons glyph font only
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:window_manager/window_manager.dart';

import 'sonic_controls.dart';

/// True on the desktop platforms with a native window frame, where our custom
/// window chrome (drag-to-move top bar + [WindowControls]) applies. Mobile/web
/// have no frame, so these are no-ops there.
bool get isDesktopWindow =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Wraps the app's top bar so dragging it moves the window and double-clicking
/// toggles maximize (via [DragToMoveArea]). A pass-through off desktop. Inner
/// buttons still receive taps — the drag only starts on an actual pan.
class TopBarDragArea extends StatelessWidget {
  const TopBarDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopWindow) return child;

    return DragToMoveArea(child: child);
  }
}

/// Minimise / maximise / close buttons for the frameless window, shown in the
/// top bar in place of the removed native title-bar buttons.
class WindowControls extends HookWidget {
  const WindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    final isMaximized = useState(false);

    useEffect(() {
      final listener = _MaxListener((value) => isMaximized.value = value);

      windowManager.addListener(listener);
      windowManager.isMaximized().then((value) => isMaximized.value = value);

      return () => windowManager.removeListener(listener);
    }, const []);

    Future<void> toggleMaximize() async {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    }

    return Row(
      mainAxisSize: .min,
      children: [
        SonicIconButton(
          icon: Icons.remove,
          size: 18,
          padding: const EdgeInsets.all(6),
          onPressed: windowManager.minimize,
        ),
        SonicIconButton(
          icon: isMaximized.value ? Icons.filter_none : Icons.crop_square,
          size: 15,
          padding: const EdgeInsets.all(6),
          onPressed: toggleMaximize,
        ),
        SonicIconButton(
          icon: Icons.close,
          size: 18,
          padding: const EdgeInsets.all(6),
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

class _MaxListener with WindowListener {
  _MaxListener(this._onChanged);

  final void Function(bool) _onChanged;

  @override
  void onWindowMaximize() => _onChanged(true);

  @override
  void onWindowUnmaximize() => _onChanged(false);
}
