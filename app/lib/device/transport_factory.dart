// Selects the Transport implementations for the current platform: the native
// midir/btleplug plugins on desktop, the Web MIDI / Web Bluetooth packages on
// web. Callers use `createTransport`; the conditional export wires the right
// side at compile time so the native plugin symbols are never referenced in a
// web build.
export 'transport_factory_io.dart'
    if (dart.library.js_interop) 'transport_factory_web.dart';
