#!/bin/bash
set -euo pipefail

SCI_DIR="$HOME/.sci"
SCI_REPO="https://github.com/OWNER/sci.git"

echo ""
echo "  🔒 SCI — Safe Claude Integration"
echo "  Installing..."
echo ""

if [ -d "$SCI_DIR/.git" ]; then
  echo "  → Updating existing installation..."
  git -C "$SCI_DIR" pull --quiet
else
  if [ -d "$SCI_DIR" ]; then
    # Config exists but not a git repo — backup and reclone
    cp -r "$SCI_DIR" "${SCI_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    rm -rf "$SCI_DIR"
  fi
  git clone --quiet "$SCI_REPO" "$SCI_DIR"
fi

chmod +x "$SCI_DIR/sci"
find "$SCI_DIR/lib" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find "$SCI_DIR/hooks" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

SHELL_RC="$HOME/.zshrc"
if ! grep -q '# SCI — Safe Claude Integration' "$SHELL_RC" 2>/dev/null; then
  {
    echo ''
    echo '# SCI — Safe Claude Integration'
    echo 'export PATH="$HOME/.sci:$PATH"'
  } >> "$SHELL_RC"
  echo "  → Added to PATH in $SHELL_RC"
fi

echo ""
echo "  ✅ Installed. Restart terminal or run:"
echo "     source ~/.zshrc"
echo ""
echo "  Then start with:"
echo "     sci setup"
echo ""
