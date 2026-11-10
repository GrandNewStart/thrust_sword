#!/bin/zsh
# Build the game and install it on a connected iPhone.
# Usage: tools/ios_deploy.sh            (first connected iPhone)
# Needs: iPhone connected by USB (or paired over Wi-Fi), unlocked, Developer Mode on.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="SwordThruster"
BUNDLE_ID="com.jinwoo.swordthruster"
TEAM="Q82L72UCXN"
OUT="build/ios"

echo "▸ Finding iPhone…"
JSON=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
read -r DEVICE_ID UDID DEVICE_NAME <<< "$(python3 - "$JSON" << 'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    if hw.get("platform") == "iOS" and hw.get("reality") == "physical" and conn.get("pairingState") == "paired":
        print(d["identifier"], hw.get("udid", ""), d.get("deviceProperties", {}).get("name", "iPhone").replace(" ", "_"))
        break
PY
)"
rm -f "$JSON"
if [[ -z "${DEVICE_ID:-}" ]]; then
  echo "✗ No paired iPhone found. Connect it by USB, unlock it, tap 'Trust', and turn on Developer Mode."
  exit 1
fi
echo "  $DEVICE_NAME ($UDID)"

echo "▸ Exporting Xcode project from Godot…"
rm -rf "$OUT" && mkdir -p "$OUT" && touch build/.gdignore  # keep Godot from importing build output
godot --headless --path . --export-debug "iOS" "$OUT/$NAME.ipa" 2>&1 | grep -E "ERROR|error" || true
[[ -d "$OUT/$NAME.xcodeproj" ]] || { echo "✗ Godot export failed"; exit 1; }

echo "▸ Building and signing…"
xcodebuild -project "$OUT/$NAME.xcodeproj" -scheme "$NAME" -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$OUT/dd" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" build -quiet

APP=$(ls -d "$OUT"/dd/Build/Products/Debug-iphoneos/*.app | head -1)
echo "▸ Installing…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" >/dev/null
echo "▸ Launching…"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null
echo "✓ Running on $DEVICE_NAME"
