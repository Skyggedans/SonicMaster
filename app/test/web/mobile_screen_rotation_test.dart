@TestOn('chrome')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/state/mobile_screen.dart';
import 'package:sonicmaster/state/mobile_screen_web.dart';
import 'package:web/web.dart' as web;

JSObject get _object => globalContext['Object']! as JSObject;

/// A scripted browser: shadows the screen, document and window properties the
/// browser MobileScreen reads, and records what it asks for. [restore] undoes
/// it all.
class _Env {
  _Env({
    String orientation = 'portrait-primary',
    int width = 400,
    int height = 800,
    bool isFullscreenEnabled = true,
    bool isDisplayModeFullscreen = false,
  }) : orientationType = orientation {
    final screen = web.window.screen;
    final document = web.document;
    final root = document.documentElement!;

    getter(screen, 'width', () => width.toJS);
    getter(screen, 'height', () => height.toJS);
    getter(document, 'fullscreenEnabled', () => isFullscreenEnabled.toJS);
    getter(document, 'fullscreenElement', () => isInFullscreen ? root : null);
    getter(screen.orientation, 'type', () => orientationType.toJS);
    value(
      screen.orientation,
      'lock',
      ((JSAny? type) {
        lockCalls.add((type! as JSString).toDart);

        return lockBehaviour().toJS;
      }).toJS,
    );
    value(
      root,
      'requestFullscreen',
      ((JSAny? options) {
        requestInsideDispatch.add(isInsideDispatch);
        requestNavigationUI.add(
          options == null
              ? null
              : ((options as JSObject)['navigationUI'] as JSString?)?.toDart,
        );

        return requestBehaviour().toJS;
      }).toJS,
    );
    value(
      document,
      'exitFullscreen',
      (() {
        exitCalls++;
        isInFullscreen = false;

        return Future<JSAny?>.value().toJS;
      }).toJS,
    );
    value(
      web.window,
      'matchMedia',
      ((JSAny? query) {
        final text = (query! as JSString).toDart;

        return JSObject()
          ..['matches'] =
              (isDisplayModeFullscreen &&
                      text.contains('display-mode: fullscreen'))
                  .toJS;
      }).toJS,
      isOriginalRestored: true,
    );
  }

  String orientationType;
  bool isInFullscreen = false;
  bool isInsideDispatch = false;
  int exitCalls = 0;
  final requestInsideDispatch = <bool>[];
  final requestNavigationUI = <String?>[];
  final lockCalls = <String>[];
  Future<JSAny?> Function() lockBehaviour = () => Future<JSAny?>.value();
  Future<JSAny?> Function() requestBehaviour = () => Future<JSAny?>.value();

  final _undo = <void Function()>[];

  void getter(JSObject target, String name, JSAny? Function() read) {
    final descriptor = JSObject()
      ..['configurable'] = true.toJS
      ..['get'] = read.toJS;

    _object.callMethod<JSAny?>(
      'defineProperty'.toJS,
      target,
      name.toJS,
      descriptor,
    );
    _undo.add(() => target.delete(name.toJS));
  }

  void value(
    JSObject target,
    String name,
    JSAny? v, {
    bool isOriginalRestored = false,
  }) {
    final original = target.getProperty<JSAny?>(name.toJS);
    final descriptor = JSObject()
      ..['configurable'] = true.toJS
      ..['writable'] = true.toJS
      ..['value'] = v;

    _object.callMethod<JSAny?>(
      'defineProperty'.toJS,
      target,
      name.toJS,
      descriptor,
    );
    _undo.add(
      isOriginalRestored
          ? () => target.setProperty(name.toJS, original)
          : () => target.delete(name.toJS),
    );
  }

  /// Turns the device: the type changes, then 'change' fires, and the request
  /// is recorded as in-dispatch only while the event is being dispatched.
  void rotateTo(String type) {
    orientationType = type;
    isInsideDispatch = true;

    try {
      web.window.screen.orientation.dispatchEvent(web.Event('change'));
    } finally {
      isInsideDispatch = false;
    }
  }

  void restore() {
    for (final undo in _undo.reversed) {
      undo();
    }

    _undo.clear();
  }
}

/// The browser MobileScreen's rotation, fullscreen and lock paths, driven in
/// real Chrome through [_Env]. Pins what the plumbing tests cannot:
/// * the fullscreen request runs synchronously inside the orientation
///   'change' dispatch (Chromium refuses it after an await or a microtask);
/// * auto-fullscreen and the landscape hold are for phones only;
/// * an installed app (`display-mode: fullscreen`) locks once at startup;
/// * dispose disarms the orientation listener.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  late _Env env;

  MobileScreen start(_Env e, {TargetPlatform platform = .android}) {
    env = e;
    addTearDown(e.restore);
    debugDefaultTargetPlatformOverride = platform;

    final screen = createMobileScreen();

    addTearDown(screen.dispose);

    return screen;
  }

  test('gates: android phone with fullscreen enabled is fully capable', () {
    final screen = start(_Env());

    expect(screen.isTouchBrowser, isTrue);
    expect(screen.isPhoneScreen, isTrue);
    expect(screen.isFullscreenAvailable, isTrue);
    expect(screen.isLandscapeLockSupported, isTrue);
    expect(
      env.lockCalls,
      isEmpty,
      reason: 'no startup lock outside display-mode',
    );
  });

  test('portrait -> landscape requests fullscreen SYNCHRONOUSLY in change, '
      'with navigationUI hide, then locks landscape', () async {
    start(_Env());

    env.rotateTo('landscape-primary');

    expect(env.requestInsideDispatch, [true]);
    expect(env.requestNavigationUI, ['hide']);
    expect(env.lockCalls, isEmpty, reason: 'lock waits for the request');

    await Future<void>.delayed(Duration.zero);

    expect(env.lockCalls, ['landscape']);
  });

  test('a flip between the two landscapes requests nothing more', () async {
    start(_Env());

    env.rotateTo('landscape-primary');
    await Future<void>.delayed(Duration.zero);
    env.rotateTo('landscape-secondary');
    await Future<void>.delayed(Duration.zero);

    expect(env.requestInsideDispatch, hasLength(1));
  });

  test('landscape -> portrait -> landscape asks again', () async {
    start(_Env());

    env.rotateTo('landscape-primary');
    env.isInFullscreen = true; // the grant took effect
    env.rotateTo('portrait-primary');
    env.isInFullscreen = false; // user left fullscreen
    env.rotateTo('landscape-primary');

    expect(env.requestInsideDispatch, [true, true]);
  });

  test('already fullscreen: a turn into landscape requests nothing', () {
    final e = _Env()..isInFullscreen = true;

    start(e);
    env.rotateTo('landscape-primary');

    expect(env.requestInsideDispatch, isEmpty);
  });

  test('a tablet (short side >= 600) never arms auto-fullscreen', () {
    final screen = start(_Env(width: 800, height: 1280));

    expect(screen.isPhoneScreen, isFalse);

    env.rotateTo('landscape-primary');

    expect(env.requestInsideDispatch, isEmpty);
  });

  test('iOS: touch, but no lock support -> never arms', () {
    final screen = start(_Env(), platform: .iOS);

    expect(screen.isTouchBrowser, isTrue);
    expect(screen.isLandscapeLockSupported, isFalse);

    env.rotateTo('landscape-primary');

    expect(env.requestInsideDispatch, isEmpty);
  });

  test('fullscreenEnabled false: unavailable, never arms', () {
    final screen = start(_Env(isFullscreenEnabled: false));

    expect(screen.isFullscreenAvailable, isFalse);

    env.rotateTo('landscape-primary');

    expect(env.requestInsideDispatch, isEmpty);
  });

  test('dispose disarms the orientation listener', () {
    final screen = start(_Env());

    screen.dispose();
    env.rotateTo('landscape-primary');

    expect(env.requestInsideDispatch, isEmpty);
  });

  test('display-mode: fullscreen on a lockable phone locks ONCE at startup, '
      'offers no fullscreen, never auto-requests', () async {
    final screen = start(_Env(isDisplayModeFullscreen: true));

    expect(env.lockCalls, ['landscape']);
    expect(screen.isFullscreenAvailable, isFalse);

    env.rotateTo('landscape-primary');
    await Future<void>.delayed(Duration.zero);

    expect(env.requestInsideDispatch, isEmpty);
    expect(env.lockCalls, ['landscape']);
  });

  test('display-mode: fullscreen on a tablet does not lock', () {
    start(_Env(isDisplayModeFullscreen: true, width: 800, height: 1280));

    expect(env.lockCalls, isEmpty);
  });

  test('enterLandscapeFullscreen requests synchronously, then locks', () async {
    final screen = start(_Env());
    final done = screen.enterLandscapeFullscreen();

    expect(env.requestInsideDispatch, [
      false,
    ], reason: 'called before any await');
    expect(env.requestNavigationUI, ['hide']);

    await done;

    expect(env.lockCalls, ['landscape']);
  });

  // The toggle on a portrait tablet: fullscreen, but no lock, so the tablet
  // keeps its portrait compact layout (and the toggle with it).
  test('a tablet enters fullscreen without the landscape hold', () async {
    final screen = start(_Env(width: 800, height: 1280));

    await screen.enterLandscapeFullscreen();

    expect(env.requestNavigationUI, ['hide']);
    expect(env.lockCalls, isEmpty);
  });

  test('a refused request leaves no lock and does not throw', () async {
    final screen = start(_Env());

    env.requestBehaviour = () =>
        Future<JSAny?>.error(StateError('NotAllowedError'));

    await expectLater(screen.enterLandscapeFullscreen(), completes);
    expect(env.lockCalls, isEmpty);
  });

  test('a refused lock does not throw', () async {
    final screen = start(_Env());

    env.lockBehaviour = () => Future<JSAny?>.error(StateError('refused'));

    await expectLater(screen.enterLandscapeFullscreen(), completes);
    expect(env.lockCalls, ['landscape']);
  });

  test('already fullscreen: enter only locks (no second request)', () async {
    final e = _Env()..isInFullscreen = true;
    final screen = start(e);

    await screen.enterLandscapeFullscreen();

    expect(env.requestInsideDispatch, isEmpty);
    expect(env.lockCalls, ['landscape']);
  });

  test(
    'exitFullscreen calls document.exitFullscreen only when fullscreen',
    () async {
      final screen = start(_Env());

      await screen.exitFullscreen();

      expect(env.exitCalls, 0);

      env.isInFullscreen = true;
      await screen.exitFullscreen();

      expect(env.exitCalls, 1);
    },
  );

  test('fullscreenchange reports the live state', () async {
    final screen = start(_Env());
    final events = <bool>[];
    final subscription = screen.fullscreenChanges.listen(events.add);

    addTearDown(subscription.cancel);
    env.isInFullscreen = true;
    web.document.dispatchEvent(web.Event('fullscreenchange'));
    env.isInFullscreen = false;
    web.document.dispatchEvent(web.Event('fullscreenchange'));
    await Future<void>.delayed(Duration.zero);

    expect(events, [true, false]);
  });

  test('requestFullscreen that throws synchronously is swallowed', () async {
    final screen = start(_Env());

    env.requestBehaviour = () => throw StateError('sync throw');

    await expectLater(screen.enterLandscapeFullscreen(), completes);
    expect(env.lockCalls, isEmpty);
  });
}
