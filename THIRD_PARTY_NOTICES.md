# Third-party notices

SonicMaster is licensed under the MIT License (see [LICENSE](LICENSE)). It
bundles and/or depends on third-party components under their own licenses,
acknowledged below.

## Bundled assets

### Oswald (font)

Copyright 2016 The Oswald Project Authors
(https://github.com/googlefonts/OswaldFont)

Licensed under the SIL Open Font License, Version 1.1. The `Oswald.ttf` file is
embedded in the application; the full license text ships alongside it at
[`app/assets/fonts/OFL.txt`](app/assets/fonts/OFL.txt) and is reproduced in the
distributed packages.

## Dependencies

The application links Dart/Flutter packages and native Rust crates, each under
its own license (predominantly BSD-3-Clause, MIT, and Apache-2.0):

- Flutter/Dart packages — see each package's entry on https://pub.dev and the
  license bundle Flutter generates (`flutter build` / the in-app licenses page).
- Native FFI plugins and crates — `flutter_midir` (midir), `flutter_btleplug`
  (btleplug), `flutter_rust_bridge`, `realfft`, `serde`/`serde_json`; see each
  crate's license on https://crates.io.

Run `flutter pub deps` / inspect `Cargo.lock` for the exact resolved versions.
