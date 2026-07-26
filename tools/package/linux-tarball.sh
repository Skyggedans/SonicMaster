#!/usr/bin/env bash
# Build a portable Linux tarball of SonicMaster.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/app"
VERSION="$(grep '^version:' "$APP/pubspec.yaml" | head -1 | sed 's/version:[[:space:]]*//; s/+.*//')"
NAME="sonicmaster-$VERSION-linux-x64"
BUNDLE="$APP/build/linux/x64/release/bundle"
STAGE="$ROOT/dist/$NAME"
OUT="$ROOT/dist/$NAME.tar.gz"

echo "==> Building release bundle (v$VERSION)"
( cd "$APP" && flutter build linux --release )

echo "==> Staging $STAGE"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -a "$BUNDLE/." "$STAGE/"
cp "$ROOT/packaging/linux/dev.skyggedans.sonicmaster.desktop" "$STAGE/"
cp "$ROOT/packaging/linux/dev.skyggedans.sonicmaster.png" "$STAGE/"
cp "$ROOT/packaging/linux/README.txt" "$STAGE/"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/"

# A tiny installer that drops a menu entry pointing at wherever the user unpacked.
cat > "$STAGE/install.sh" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/512x512/apps"
mkdir -p "$APPS" "$ICONS"
cp "$HERE/dev.skyggedans.sonicmaster.png" "$ICONS/dev.skyggedans.sonicmaster.png"
gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
# Rewrite Exec= to this install location. Pure bash (no sed/awk) so the path is
# safe even if it contains metacharacters, and the value is double-quoted so
# reserved chars like & or | in the path stay valid per the .desktop spec.
while IFS= read -r line; do
  case "$line" in
    Exec=*) printf 'Exec="%s/sonicmaster"\n' "$HERE" ;;
    *) printf '%s\n' "$line" ;;
  esac
done < "$HERE/dev.skyggedans.sonicmaster.desktop" > "$APPS/dev.skyggedans.sonicmaster.desktop"
echo "Installed menu entry -> $APPS/dev.skyggedans.sonicmaster.desktop"
INSTALL
chmod +x "$STAGE/install.sh"

echo "==> Archiving $OUT"
rm -f "$OUT"
( cd "$ROOT/dist" && tar czf "$OUT" "$NAME" )
rm -rf "$STAGE"
echo "==> Done: $OUT ($(du -h "$OUT" | cut -f1))"
