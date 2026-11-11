#!/bin/zsh
# Export a desktop build.
# Usage: tools/build.sh [macos|windows|linux|all] [--run]
#   macos   -> build/macos/ThrustSword.app   (ad-hoc signed, universal)
#   windows -> build/windows/ThrustSword.exe (x86_64)
#   linux   -> build/linux/ThrustSword.x86_64
#   --run   launch the macOS app after building
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}
mkdir -p build && touch build/.gdignore  # keep Godot from importing build output

export_one() {  # <preset name> <output path>
  local preset=$1 out=$2
  mkdir -p "$(dirname "$out")"
  rm -rf "$out"
  echo "▸ Exporting $preset…"
  "$GODOT" --headless --path . --export-release "$preset" "$out" 2>&1 | grep -E "ERROR|error" || true
  [[ -e "$out" ]] || { echo "✗ $preset export failed"; exit 1; }
  echo "✓ $out ($(du -sh "$out" | cut -f1))"
}

target=${1:-macos}
case $target in
  macos)   export_one "macOS" build/macos/ThrustSword.app ;;
  windows) export_one "Windows" build/windows/ThrustSword.exe ;;
  linux)   export_one "Linux" build/linux/ThrustSword.x86_64 ;;
  all)     export_one "macOS" build/macos/ThrustSword.app
           export_one "Windows" build/windows/ThrustSword.exe
           export_one "Linux" build/linux/ThrustSword.x86_64 ;;
  *) echo "usage: tools/build.sh [macos|windows|linux|all] [--run]"; exit 2 ;;
esac
if [[ "${2:-}" == "--run" && -d build/macos/ThrustSword.app ]]; then
  open build/macos/ThrustSword.app
fi
