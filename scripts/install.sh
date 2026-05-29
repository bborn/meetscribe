#!/bin/zsh
# install.sh — copy meetscribe + meetscribe-bg into a directory on your PATH.
# By default installs to ~/.local/bin (XDG convention).

set -euo pipefail
ROOT="${0:a:h}/.."
DEST="${MEETSCRIBE_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$DEST"
install -m 0755 "$ROOT/bin/meetscribe"    "$DEST/meetscribe"
install -m 0755 "$ROOT/bin/meetscribe-bg" "$DEST/meetscribe-bg"
echo "Installed:"
echo "  $DEST/meetscribe"
echo "  $DEST/meetscribe-bg"
case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo; echo "NOTE: $DEST is not on your PATH. Add this to your shell rc:"; echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
