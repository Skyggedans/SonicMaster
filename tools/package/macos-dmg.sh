#!/usr/bin/env bash
# Build the macOS .app and wrap it in a drag-to-install .dmg. Run ON macOS.
#
#   bash tools/package/macos-dmg.sh
#   -> dist/SonicMaster-<version>-macos.dmg
#
# Optional signing / notarization (for distribution outside the App Store):
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=sonicmaster-notary \
#   bash tools/package/macos-dmg.sh
#
# - SIGN_ID: a "Developer ID Application" identity in the login keychain. When
#   set, the .app is deep-signed with the hardened runtime + a secure timestamp,
#   and the .dmg is signed too.
# - NOTARY_PROFILE: a keychain profile created once with
#     xcrun notarytool store-credentials <name> --apple-id <id> --team-id <team> --password <app-specific-pw>
#   When set (and SIGN_ID is set), the .dmg is submitted to Apple, waited on,
#   and stapled so it passes Gatekeeper on a clean machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/app"
DIST="$ROOT/dist"
VERSION="$(grep '^version:' "$APP/pubspec.yaml" | head -1 | sed 's/version:[[:space:]]*//; s/+.*//')"
BUILT="$APP/build/macos/Build/Products/Release/SonicMaster.app"
VOLNAME="SonicMaster $VERSION"
OUT="$DIST/SonicMaster-$VERSION-macos.dmg"

echo "==> Building release .app (v$VERSION)"
( cd "$APP" && flutter build macos --release )

if [ ! -d "$BUILT" ]; then
  echo "ERROR: $BUILT not found (is macOS PRODUCT_NAME = SonicMaster?)." >&2
  exit 1
fi

if [ -n "${SIGN_ID:-}" ]; then
  echo "==> Codesigning the .app (hardened runtime) with: $SIGN_ID"
  codesign --deep --force --options runtime --timestamp --sign "$SIGN_ID" "$BUILT"
  codesign --verify --deep --strict --verbose=1 "$BUILT"
fi

echo "==> Building the .dmg (hdiutil)"
mkdir -p "$DIST"
rm -f "$OUT"

# Stage the .app next to an /Applications symlink for the standard drag-to-
# install layout.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$BUILT" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/"

hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ \
  -ov -format UDZO "$OUT"

if [ -n "${SIGN_ID:-}" ]; then
  echo "==> Signing the .dmg"
  codesign --force --timestamp --sign "$SIGN_ID" "$OUT"

  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing (profile: $NOTARY_PROFILE)"
    xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUT"
    xcrun stapler validate "$OUT"
  else
    echo "    (set NOTARY_PROFILE to notarize + staple for Gatekeeper)"
  fi
fi

echo "==> Done: $OUT ($(du -h "$OUT" | cut -f1))"
