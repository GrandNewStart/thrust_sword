#!/bin/zsh
# Build the macOS app and (optionally) launch it.
# Usage: tools/macos_build.sh          build + launch
#        tools/macos_build.sh --no-run build only
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/macos"
mkdir -p "$OUT" && touch build/.gdignore  # keep Godot from importing build output
rm -rf "$OUT/SwordThruster.app"
echo "▸ Exporting macOS app…"
godot --headless --path . --export-release "macOS" "$OUT/SwordThruster.app" 2>&1 | grep -E "ERROR|error" || true
[[ -d "$OUT/SwordThruster.app" ]] || { echo "✗ Export failed"; exit 1; }
echo "✓ $OUT/SwordThruster.app ($(du -sh "$OUT/SwordThruster.app" | cut -f1))"
if [[ "${1:-}" != "--no-run" ]]; then
  open "$OUT/SwordThruster.app"
fi
