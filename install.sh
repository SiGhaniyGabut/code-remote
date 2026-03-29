#!/usr/bin/env bash

set -e

INSTALL_DIR="$HOME/.local/share/code-remote"
SCRIPT_URL="https://raw.githubusercontent.com/SiGhaniyGabut/code-remote/main/code-remote.sh"
BASHRC="$HOME/.bashrc"

echo "Installing cr..."

mkdir -p "$INSTALL_DIR"

if command -v curl &>/dev/null; then
  curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/code-remote.sh"
elif command -v wget &>/dev/null; then
  wget -qO "$INSTALL_DIR/code-remote.sh" "$SCRIPT_URL"
else
  echo "Error: curl or wget required." >&2
  exit 1
fi

chmod +x "$INSTALL_DIR/code-remote.sh"

SOURCE_LINE="source $INSTALL_DIR/code-remote.sh"

if ! grep -qF "$SOURCE_LINE" "$BASHRC" 2>/dev/null; then
  echo "" >> "$BASHRC"
  echo "# cr - VSCode Remote helper" >> "$BASHRC"
  echo "$SOURCE_LINE" >> "$BASHRC"
  echo "Added to $BASHRC"
else
  echo "Already in $BASHRC"
fi

echo "Done. Run 'source ~/.bashrc' or open a new terminal."
