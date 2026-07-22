# flutter_midir

A thin, reusable Flutter **MIDI transport** plugin backed by the Rust
[`midir`](https://crates.io/crates/midir) crate via
[`flutter_rust_bridge`](https://cjycode.com/flutter_rust_bridge/) (2.12.0).

Cross-platform desktop MIDI: **Linux (ALSA)**, **macOS (CoreMIDI)**, **Windows
(WinMM)**. The plugin is protocol-agnostic — it only enumerates ports, opens one
input+output connection, sends raw bytes, and streams received bytes. All
SysEx / framing / CRC logic belongs in the consuming app.

## API

```dart
import 'package:flutter_midir/flutter_midir.dart';

await initMidi(); // once at startup

final ports = await listMidiPorts(); // List<MidiPort> (name + direction)

final conn = await MidiConnection.open(
  inputPortName: 'Smart Box',   // matched by substring of the port name
  outputPortName: 'Smart Box',
);
conn.incoming.listen((Uint8List bytes) { /* one received message */ });
await conn.send(bytes); // raw wire bytes (e.g. a bare F0..F7 over USB MIDI)
await conn.close();
```

Only one connection exists at a time on the native side; opening a new one
replaces the previous.

## Prerequisites

- **Rust** toolchain (built automatically via cargokit during `flutter build`).
- **Linux:** ALSA development headers — `alsa-lib-devel` (Fedora) /
  `libasound2-dev` (Debian/Ubuntu). Required to compile `midir`.

## Regenerating bindings

The Rust API lives in `rust/src/api/midi.rs`. After changing it:

```bash
flutter_rust_bridge_codegen generate   # run from this package root
```

## Notes

- Port names on Linux/ALSA include a client:port suffix (e.g.
  `Smart Box:Smart Box MIDI 1 36:0`) that varies across reconnects, so match by
  a stable substring rather than the full name.
- This package targets desktop; the generated `android/`/`ios/` folders are
  unused.
