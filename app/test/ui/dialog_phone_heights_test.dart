import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/global_settings.dart';
import 'package:sonicmaster/model/preset_ref.dart';
import 'package:sonicmaster/state/data_providers.dart';
import 'package:sonicmaster/state/names_providers.dart';
import 'package:sonicmaster/state/preset_providers.dart';
import 'package:sonicmaster/theme/app_text.dart';
import 'package:sonicmaster/ui/device_dialog.dart';
import 'package:sonicmaster/ui/global_settings_dialog.dart';
import 'package:sonicmaster/ui/import_dialogs.dart';
import 'package:sonicmaster/ui/save_preset_dialog.dart';
import 'package:sonicmaster/ui/sonic_controls.dart';
import 'package:sonicmaster/ui/unsaved_changes_dialog.dart';
import 'package:sonicmaster/ui/user_ir_actions.dart';
import 'package:sonicmaster/ui/user_profile_actions.dart';

import '../support/sonic_host.dart';
import '../support/test_assets.dart';
import '../support/view_helpers.dart';

/// One pop-up under test: the [home] it opens from, its provider
/// [overrides], how to [open] it, its [title] (to find its plate), the
/// [action] that must stay reachable, and whether a name field autofocuses
/// (it must then sit above the keyboard).
typedef DialogCase = ({
  String name,
  Widget home,
  List<Override> overrides,
  Future<void> Function(WidgetTester tester, BuildContext context) open,
  String title,
  String action,
  bool hasField,
});

const _current = PresetRef(.user, 5);

const _irActions = Center(
  child: UserIrActions(slot: 0, isEnabled: true, currentName: 'My IR'),
);

const _profileActions = Center(
  child: UserProfileActions(slot: 0, isEnabled: true, currentName: 'My NAM'),
);

final _assets = loadTestDataAssets();

final _settingsOverrides = <Override>[
  dataAssetsProvider.overrideWith((_) => _assets),
  globalSettingsProvider.overrideWith(
    (_) => const GlobalSettings(
      globalVolume: 50,
      inputLevel: 0,
      fxRecLevel: 0,
      monitorLevel: 0,
      btRecLevel: 0,
    ),
  ),
];

Future<void> _show(
  WidgetTester tester,
  BuildContext context,
  Widget dialog, {
  bool isDismissible = true,
}) async {
  unawaited(
    showSonicDialog<void>(
      context: context,
      barrierDismissible: isDismissible,
      builder: (_) => dialog,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapLabel(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Widget _deviceShell(Widget content) => DeviceDialogShell(
  content: content,
  transport: .usb,
  onTransport: (_) {},
  onRescan: () {},
);

final _cases = <DialogCase>[
  (
    name: 'unsaved changes',
    home: const SizedBox.shrink(),
    overrides: const [],
    open: (tester, context) async {
      unawaited(showUnsavedChangesDialog(context));
      await tester.pumpAndSettle();
    },
    title: 'Discard unsaved changes?',
    action: 'Discard',
    hasField: false,
  ),
  (
    name: 'save preset',
    home: const SizedBox.shrink(),
    overrides: [
      currentPresetProvider.overrideWith((_) => _current),
      presetNamesProvider.overrideWith((_) => {_current: 'MyPatch'}),
    ],
    open: (tester, context) async {
      unawaited(showSavePresetDialog(context));
      await tester.pumpAndSettle();
    },
    title: 'Save preset',
    action: 'Save',
    hasField: true,
  ),
  (
    name: 'rename user IR',
    home: _irActions,
    overrides: const [],
    open: (tester, _) => _tapLabel(tester, 'Name…'),
    title: 'Rename User IR 1',
    action: 'Rename',
    hasField: true,
  ),
  (
    name: 'rename user profile',
    home: _profileActions,
    overrides: const [],
    open: (tester, _) => _tapLabel(tester, 'Name…'),
    title: 'Rename User Profile 1',
    action: 'Rename',
    hasField: true,
  ),
  (
    name: 'factory reset confirm',
    home: const SizedBox.shrink(),
    overrides: _settingsOverrides,
    open: (tester, context) async {
      await _show(tester, context, const GlobalSettingsDialog());

      final reset = find.text('Reset to factory settings');

      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();
    },
    title: 'Reset to factory settings?',
    action: 'Reset',
    hasField: false,
  ),
  (
    name: 'import progress',
    home: const SizedBox.shrink(),
    overrides: [
      presetLoadStatusProvider.overrideWith((_) => 'Uploading chunk 12/30…'),
      importProgressProvider.overrideWith((_) => 0.4),
    ],
    open: (tester, context) async {
      unawaited(
        showSonicDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              const ImportProgressDialog(title: 'Importing to User IR 1'),
        ),
      );
      // The spinner never settles: pump past the 160-ms fade instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    },
    title: 'Importing to User IR 1',
    action: '40%',
    hasField: false,
  ),
  (
    name: 'import error',
    home: const SizedBox.shrink(),
    overrides: const [],
    open: (tester, context) => _show(
      tester,
      context,
      const ImportErrorDialog(
        title: 'Import failed',
        message:
            'This .nam is an LSTM model, which the clone converter cannot '
            'convert. Pick a WaveNet capture instead.',
        showSupportedFormats: true,
      ),
    ),
    title: 'Import failed',
    action: 'OK',
    hasField: false,
  ),
  (
    name: 'device picker, list',
    home: const SizedBox.shrink(),
    overrides: const [],
    open: (tester, context) => _show(
      tester,
      context,
      _deviceShell(
        ListView(
          padding: EdgeInsets.zero,
          children: [
            for (final i in Iterable<int>.generate(8))
              SizedBox(height: 64, child: Text('Pedal $i')),
          ],
        ),
      ),
    ),
    title: 'Select a device',
    action: 'Cancel',
    hasField: false,
  ),
  (
    name: 'device picker, nothing found',
    home: const SizedBox.shrink(),
    overrides: const [],
    open: (tester, context) => _show(
      tester,
      context,
      _deviceShell(
        const Center(
          child: Text('No USB MIDI devices found', style: AppText.dialogBody),
        ),
      ),
    ),
    title: 'Select a device',
    action: 'Cancel',
    hasField: false,
  ),
  (
    name: 'device picker, error',
    home: const SizedBox.shrink(),
    overrides: const [],
    open: (tester, context) => _show(
      tester,
      context,
      _deviceShell(
        const Center(
          child: Text(
            'Web Bluetooth is not available.\n'
            'Use Chrome, Edge, or Opera. On Linux, enable\n'
            'chrome://flags/#enable-experimental-web-platform-features',
            textAlign: .center,
            style: AppText.dialogBody,
          ),
        ),
      ),
    ),
    title: 'Select a device',
    action: 'Cancel',
    hasField: false,
  ),
  (
    name: 'device picker, scanning',
    home: const SizedBox.shrink(),
    overrides: const [],
    open: (tester, context) async {
      // The real picker: under flutter test its USB scan never finishes, so
      // it stays on the spinner (no pending timers).
      unawaited(
        showSonicDialog<void>(
          context: context,
          builder: (_) => const DeviceDialog(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    },
    title: 'Select a device',
    action: 'Cancel',
    hasField: false,
  ),
  (
    name: 'settings',
    home: const SizedBox.shrink(),
    overrides: _settingsOverrides,
    open: (tester, context) =>
        _show(tester, context, const GlobalSettingsDialog()),
    title: 'Settings',
    action: 'Close',
    hasField: false,
  ),
];

/// When the soft keyboard comes up: never, before the dialog opens (a value
/// was being typed elsewhere), or after (the dialog's own field autofocused).
enum _Keyboard { none, before, after }

void main() {
  const sizes = [
    Size(852, 393),
    Size(780, 360),
    Size(640, 300),
    Size(740, 280),
    Size(568, 320),
  ];
  const keyboardHeight = 180.0;

  for (final dialog in _cases) {
    for (final size in sizes) {
      for (final keyboard
          in dialog.hasField ? _Keyboard.values : const [_Keyboard.none]) {
        final where = '${size.width.toInt()}x${size.height.toInt()}';
        final label = switch (keyboard) {
          .none => '${dialog.name} at $where',
          .before => '${dialog.name} at $where, keyboard already up',
          .after => '${dialog.name} at $where, keyboard rising after open',
        };

        testWidgets(label, (tester) async {
          final context = await pumpSonicHost(
            tester,
            size: size,
            keyboard: keyboard == .before ? keyboardHeight : 0,
            overrides: dialog.overrides,
            home: dialog.home,
          );

          await dialog.open(tester, context);

          if (keyboard == .after) {
            await setKeyboard(tester, keyboardHeight);
            await tester.pumpAndSettle();
          }

          final visible =
              Offset.zero &
              Size(
                size.width,
                size.height - (keyboard == .none ? 0 : keyboardHeight),
              );

          expect(tester.takeException(), isNull);

          if (dialog.hasField) {
            expectWithin(
              tester.getRect(find.byType(EditableText)),
              visible,
              'the name field',
            );
          }

          final action = find.text(dialog.action).last;

          await tester.ensureVisible(action);
          await tester.pump();

          expectWithin(tester.getRect(action), visible, dialog.action);
        });
      }
    }
  }

  // The regular layout is pinned: these plates sit exactly where they did
  // before SonicDialog learned to scroll and lift.
  group('regular 1280x800 plates are unchanged', () {
    for (final (name, rect) in const [
      ('unsaved changes', Rect.fromLTRB(400, 305, 880, 495)),
      ('save preset', Rect.fromLTRB(450, 270, 830, 530)),
      ('device picker, scanning', Rect.fromLTRB(420, 160, 860, 640)),
      ('settings', Rect.fromLTRB(420, 84, 860, 716)),
    ]) {
      testWidgets(name, (tester) async {
        final dialog = _cases.firstWhere((c) => c.name == name);
        final context = await pumpSonicHost(
          tester,
          overrides: dialog.overrides,
          home: dialog.home,
        );

        await dialog.open(tester, context);

        expect(
          tester.getRect(
            find.ancestor(
              of: find.text(dialog.title),
              matching: find.byType(SonicSurface),
            ),
          ),
          rect,
        );
      });
    }
  });
}
