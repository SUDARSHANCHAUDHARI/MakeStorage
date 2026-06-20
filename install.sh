#!/usr/bin/env bash
#
# MakeStorage installer — symlinks the CLI into a bin dir on PATH.
#
#   ./install.sh            # install to ~/.local/bin
#   PREFIX=/usr/local ./install.sh   # install to /usr/local/bin (may need sudo)
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="${PREFIX:-$HOME/.local}/bin"
mkdir -p "$BIN"
ln -sf "$SRC_DIR/makestorage" "$BIN/makestorage"
chmod +x "$SRC_DIR/makestorage"

echo "Installed: $BIN/makestorage"
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "Add to PATH:  export PATH=\"$BIN:\$PATH\"" ;;
esac
echo "Run: makestorage status"
