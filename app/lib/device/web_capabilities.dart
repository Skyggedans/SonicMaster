// Whether the browser exposes the APIs the web transports need. On native both
// are always available (the packages talk to the OS); on web they gate on
// `navigator.requestMIDIAccess` (Web MIDI, Chromium+Firefox) and
// `navigator.bluetooth` (Web Bluetooth, Chromium only).
export 'web_capabilities_io.dart'
    if (dart.library.js_interop) 'web_capabilities_web.dart';
