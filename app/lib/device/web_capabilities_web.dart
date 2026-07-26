import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('navigator')
external JSObject get _navigator;

/// Web MIDI (with SysEx) — Chromium (Chrome/Edge/Opera) and Firefox 108+, but
/// not Safari/iOS.
bool get isWebMidiSupported => _navigator.has('requestMIDIAccess');

/// Web Bluetooth — Chromium only (Chrome/Edge/Opera; on Linux behind a flag),
/// not Firefox or Safari.
bool get isWebBluetoothSupported => _navigator.has('bluetooth');
