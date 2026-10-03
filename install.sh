#!/bin/bash
# One-line install. Installs kbswap, then offers to swap Alt/Win on each connected
# non-Apple keyboard that has no mapping yet:
#
#   curl -fsSL https://raw.githubusercontent.com/kailin5/mac-keyboard-swap/main/install.sh | bash
#
# Non-interactive (dotfiles, new Mac): pass the keyboards to enable, no prompts.
#
#   curl -fsSL https://raw.githubusercontent.com/kailin5/mac-keyboard-swap/main/install.sh | bash -s -- 1133:50475
#
# Env: KBSWAP_BIN_DIR (default ~/.local/bin), KBSWAP_REF (git ref to install, default main).
set -euo pipefail

RAW="https://raw.githubusercontent.com/kailin5/mac-keyboard-swap/${KBSWAP_REF:-main}"
BIN_DIR="${KBSWAP_BIN_DIR:-$HOME/.local/bin}"
APPLE_VENDORS=" 1452 76 "   # USB and Bluetooth vendor IDs Apple uses

[ "$(uname -s)" = Darwin ] || { echo "kbswap: macOS only" >&2; exit 1; }

# Install: copy from a local checkout when run as ./install.sh, otherwise download.
mkdir -p "$BIN_DIR"
here=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
if [ -n "$here" ] && [ -f "$here/bin/kbswap" ]; then
  cp "$here/bin/kbswap" "$BIN_DIR/kbswap.tmp"
else
  curl -fsSL "$RAW/bin/kbswap" -o "$BIN_DIR/kbswap.tmp"
fi
chmod +x "$BIN_DIR/kbswap.tmp"
mv "$BIN_DIR/kbswap.tmp" "$BIN_DIR/kbswap"
KBSWAP="$BIN_DIR/kbswap"
echo "Installed $("$KBSWAP" version) to $KBSWAP"

# Enable: explicit IDs win; otherwise ask per keyboard when a terminal is available.
if [ $# -gt 0 ]; then
  for id in "$@"; do "$KBSWAP" enable "$id"; done
elif { : < /dev/tty; } 2>/dev/null; then
  asked=0
  while IFS=$'\t' read -r id transport state product; do
    [ -n "$id" ] || continue
    case "$APPLE_VENDORS" in *" ${id%%:*} "*) continue ;; esac
    case "$state" in
      swapped) echo "$product ($id) is already swapped." ; continue ;;
      custom)  echo "$product ($id) has a custom mapping; leaving it. Use: kbswap enable $id --force" ; continue ;;
    esac
    asked=1
    printf 'Swap Alt/Win on "%s" (%s, %s)? [y/N] ' "$product" "$id" "$transport"
    read -r answer < /dev/tty || answer=""
    case "$answer" in [yY]*) "$KBSWAP" enable "$id" ;; *) echo "Skipped." ;; esac
  done <<EOF
$("$KBSWAP" list --plain)
EOF
  [ $asked = 1 ] || echo "No unmapped non-Apple keyboards connected. Plug one in and run: kbswap list"
else
  echo "No terminal to ask on. Enable a keyboard with: $KBSWAP enable VID:PID (see: $KBSWAP list)"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo
     echo "Note: $BIN_DIR is not on your PATH. The swap already works without it; to use the"
     echo "kbswap command directly, run:  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc" ;;
esac
