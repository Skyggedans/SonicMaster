#!/usr/bin/env bash
# Regenerate all platform app icons from the master (packaging/icon/sonicmaster_icon.png).
# Requires ImageMagick (magick). Re-run after editing the master.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MASTER="$ROOT/packaging/icon/sonicmaster_icon.png"
[ -f "$MASTER" ] || { echo "missing master: $MASTER" >&2; exit 1; }
command -v magick >/dev/null || { echo "ImageMagick 'magick' required" >&2; exit 1; }

echo "==> Linux packaging icon (512)"
magick "$MASTER" -resize 512x512 "$ROOT/packaging/linux/dev.skyggedans.sonicmaster.png"

echo "==> macOS iconset"
ICO_MAC="$ROOT/app/macos/Runner/Assets.xcassets/AppIcon.appiconset"
for s in 16 32 64 128 256 512 1024; do
  magick "$MASTER" -resize ${s}x${s} "$ICO_MAC/app_icon_${s}.png"
done

echo "==> Windows .ico (multi-size)"
magick "$MASTER" -define icon:auto-resize=256,128,64,48,32,16 \
  "$ROOT/app/windows/runner/resources/app_icon.ico"

echo "==> Done."
