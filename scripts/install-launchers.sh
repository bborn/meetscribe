#!/bin/zsh
# install-launchers.sh — install the optional one-press launchers:
#   • Dock app  (~/Applications/Meeting Recorder.app)
#   • SwiftBar menu-bar plugin (if SwiftBar is installed)

set -euo pipefail
ROOT="${0:a:h}/.."

# --- Dock app ---------------------------------------------------------------
APP_PARENT="$HOME/Applications"
APP="$APP_PARENT/Meeting Recorder.app"
mkdir -p "$APP_PARENT"
rm -rf "$APP"
osacompile -o "$APP" "$ROOT/extras/dock-app/MeetingRecorder.applescript"
echo "Dock app built at: $APP"
echo "  → drag it to your Dock for one-click recording."

# --- SwiftBar plugin --------------------------------------------------------
SWIFTBAR_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
if [[ -d "$SWIFTBAR_DIR" ]]; then
  install -m 0755 "$ROOT/extras/swiftbar/meetscribe.1s.sh" "$SWIFTBAR_DIR/meetscribe.1s.sh"
  echo "SwiftBar plugin installed at: $SWIFTBAR_DIR/meetscribe.1s.sh"
else
  echo "SwiftBar plugin folder not found at $SWIFTBAR_DIR — skipping."
  echo "  (Install SwiftBar from https://github.com/swiftbar/SwiftBar, then drop"
  echo "   extras/swiftbar/meetscribe.1s.sh into its Plugins folder.)"
fi
