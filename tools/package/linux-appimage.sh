#!/usr/bin/env bash
# Build a self-contained AppImage of SonicMaster.
#
#   bash tools/package/linux-appimage.sh
#   -> dist/SonicMaster-<version>-x86_64.AppImage
#
# appimagetool is fetched automatically (cached under dist/.tools) if it isn't
# already on PATH or in $APPIMAGETOOL. The AppImage relies on the host's system
# GTK 3 + ALSA (libasound2) — true of essentially every desktop Linux; bundling
# those (linuxdeploy-plugin-gtk) would be a heavier, fragile step we skip.
set -euo pipefail

ARCH="${ARCH:-x86_64}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/app"
DIST="$ROOT/dist"
PKG="$ROOT/packaging/linux"

VERSION="$(grep '^version:' "$APP/pubspec.yaml" | head -1 | sed 's/version:[[:space:]]*//; s/+.*//')"
BUNDLE="$APP/build/linux/x64/release/bundle"
APPID="dev.skyggedans.sonicmaster"
APPDIR="$DIST/SonicMaster.AppDir"
OUT="$DIST/SonicMaster-$VERSION-$ARCH.AppImage"

mkdir -p "$DIST"

# --- appimagetool: use $APPIMAGETOOL, else PATH, else download + cache -------
fetch_appimagetool() {
  local cache="$DIST/.tools"
  local bin="$cache/appimagetool-$ARCH.AppImage"

  if [ -n "${APPIMAGETOOL:-}" ]; then
    printf '%s' "$APPIMAGETOOL"
    return
  fi

  if command -v appimagetool >/dev/null 2>&1; then
    command -v appimagetool
    return
  fi

  if [ ! -x "$bin" ]; then
    mkdir -p "$cache"
    local url="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage"
    echo "==> Fetching appimagetool ($ARCH)" >&2

    if command -v curl >/dev/null 2>&1; then
      curl -fL --retry 3 -o "$bin" "$url"
    elif command -v wget >/dev/null 2>&1; then
      wget -q -O "$bin" "$url"
    else
      echo "ERROR: need curl or wget to download appimagetool, or set APPIMAGETOOL=/path." >&2
      exit 1
    fi

    chmod +x "$bin"
  fi

  printf '%s' "$bin"
}

TOOL="$(fetch_appimagetool)"

# --- build the release bundle ------------------------------------------------
echo "==> Building release bundle (v$VERSION)"
( cd "$APP" && flutter build linux --release )

if [ ! -x "$BUNDLE/sonicmaster" ]; then
  echo "ERROR: release bundle not found at $BUNDLE (expected the 'sonicmaster' binary)." >&2
  exit 1
fi

# --- assemble the AppDir -----------------------------------------------------
echo "==> Assembling AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR"

# The Flutter bundle (sonicmaster + lib/ + data/) sits at the AppDir root; the
# executable's $ORIGIN/lib rpath then resolves the bundled Flutter/plugin libs.
cp -a "$BUNDLE/." "$APPDIR/"

# Desktop entry + icon: at the AppDir root (required by appimagetool) and under
# usr/share (so the AppImage integrates a menu entry + icon when registered).
install -Dm644 "$PKG/$APPID.desktop" "$APPDIR/$APPID.desktop"
install -Dm644 "$PKG/$APPID.desktop" "$APPDIR/usr/share/applications/$APPID.desktop"
install -Dm644 "$PKG/$APPID.png" "$APPDIR/$APPID.png"
install -Dm644 "$PKG/$APPID.png" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APPID.png"
ln -sf "$APPID.png" "$APPDIR/.DirIcon"

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/lib:${LD_LIBRARY_PATH:-}"
exec "$HERE/sonicmaster" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# --- pack --------------------------------------------------------------------
echo "==> Running appimagetool"
rm -f "$OUT"
# --appimage-extract-and-run lets the tool run without FUSE (headless / CI).
ARCH="$ARCH" "$TOOL" --appimage-extract-and-run "$APPDIR" "$OUT"
rm -rf "$APPDIR"

echo "==> Done: $OUT ($(du -h "$OUT" | cut -f1))"
