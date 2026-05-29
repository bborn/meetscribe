#!/bin/zsh
# build.sh — compile sccap and bundle it as ~/Applications/sccap.app
#
# What this does:
#   1. Compiles src/sccap.m into a native binary (ObjC, no Swift required).
#   2. Builds a tiny .app bundle around it (Info.plist, MacOS/sccap).
#   3. Ad-hoc code-signs the bundle so it gets a stable TCC identity.
#
# Why an .app bundle?
#   ScreenCaptureKit needs the Screen Recording TCC permission. When sccap is
#   launched via `open` (as meetscribe does), the app is its own "responsible
#   process" for TCC, so one permission grant works regardless of who clicked.

set -euo pipefail

ROOT="${0:a:h}/.."
SRC="$ROOT/src/sccap.m"
BIN_DIR="$ROOT/build"
APP_PARENT="${MEETSCRIBE_APP_DIR:-$HOME/Applications}"
APP="$APP_PARENT/sccap.app"

[[ -f "$SRC" ]] || { echo "src/sccap.m not found"; exit 1; }
mkdir -p "$BIN_DIR" "$APP_PARENT"

echo "==> Compiling sccap"
clang -fobjc-arc -O2 \
  -framework Foundation -framework ScreenCaptureKit \
  -framework CoreMedia  -framework CoreAudio \
  "$SRC" -o "$BIN_DIR/sccap"

echo "==> Building bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/sccap" "$APP/Contents/MacOS/sccap"
cp "$ROOT/src/Info.plist" "$APP/Contents/Info.plist"

echo "==> Ad-hoc signing"
codesign --force --sign - "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Identifier|Signature" | sed 's/^/    /'

cat <<EOF

Done.

The bundle is at: $APP

Next step — first-time permissions:
  Run \`meetscribe start\` once. It will print "capture did not start" because
  macOS hasn't been asked yet. Open System Settings → Privacy & Security and
  enable "sccap" (or "Meeting Audio Capture") in BOTH:
    • Screen Recording
    • Microphone
  Then \`meetscribe start\` for real.
EOF
