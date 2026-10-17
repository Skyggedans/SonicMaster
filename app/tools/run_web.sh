#!/usr/bin/env bash
#
# Dev-runs the Flutter Web app in Chrome with Web Bluetooth enabled.
#
# `flutter run -d chrome` launches Chrome with a THROWAWAY --user-data-dir
# (packages/flutter_tools/.../web/chrome.dart), so any chrome://flags you set in
# your normal profile do NOT apply to it. On Linux, Web Bluetooth lives behind
# the experimental-web-platform-features flag, so navigator.bluetooth is absent
# there unless we pass the switch explicitly. --web-browser-flag forwards it into
# the spawned Chrome. (localhost is a secure context, so Web MIDI/Bluetooth are
# exposed once the feature is on.)
#
# Also compiles the DSP web worker first (flutter run only builds lib/main.dart,
# never web/dsp_level_worker.dart, and its emitted JS is gitignored) so NAM→.clo
# conversion works in the dev run too. See build_web.sh for the why.
#
# Extra args are forwarded to `flutter run` (e.g. --web-port 8080).
# Run from anywhere; paths are resolved relative to the app dir.
set -euo pipefail

cd "$(dirname "$0")/.."

echo '==> Compiling DSP web worker -> web/dsp_level_worker.dart.js'
dart compile js web/dsp_level_worker.dart -o web/dsp_level_worker.dart.js

echo '==> flutter run -d chrome (Web Bluetooth enabled)'
flutter run -d chrome \
  --web-browser-flag="--enable-experimental-web-platform-features" \
  "$@"
