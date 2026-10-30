// Platform-selecting entry for the Web Worker DSP path. Web builds get the real
// `Worker`-backed implementation; every other platform gets a stub that throws
// (they take the native flutter_rust_bridge generator instead). The conditional
// export keeps `package:web` / `dart:js_interop` out of non-web builds.
export 'clo_worker_data.dart';
export 'clo_worker_stub.dart'
    if (dart.library.js_interop) 'clo_worker_web.dart';
