#!/usr/bin/env bash
# Builds Big Head Party and installs it on the iPhone plugged into this Mac.
#
#   cd ~/big-head-party && git pull && ./scripts/install-on-iphone.sh
#
# Needs: Xcode (signed in with your Apple ID under Xcode > Settings > Accounts),
# an iPhone connected by cable (tap "Trust"), and Developer Mode turned on
# (iPhone Settings > Privacy & Security > Developer Mode).
# Optional: TEAM_ID=ABCDE12345 ./scripts/install-on-iphone.sh to pick a team.
set -euo pipefail
cd "$(dirname "$0")/.."
BUNDLE=com.domqinvestments.bigheadparty
say() { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }

command -v xcodebuild >/dev/null || { echo "Xcode isn't installed. Get it from the Mac App Store, open it once, then run this again."; exit 1; }

# 1. Signing team: from TEAM_ID, else from the accounts signed into Xcode (paid team preferred).
if [ -z "${TEAM_ID:-}" ]; then
  TEAM_ID=$(defaults export com.apple.dt.Xcode - 2>/dev/null \
    | plutil -extract IDEProvisioningTeamByIdentifier json -o - - 2>/dev/null \
    | /usr/bin/python3 -c '
import json, sys
try: data = json.load(sys.stdin)
except Exception: sys.exit()
teams = [t for acct in data.values() for t in acct]
teams.sort(key=lambda t: t.get("isFreeProvisioningTeam", False))
print(teams[0]["teamID"] if teams else "")' || true)
fi
if [ -z "${TEAM_ID:-}" ]; then
  echo "No Apple ID found in Xcode. Open Xcode > Settings > Accounts, add your developer Apple ID, then run this again."
  echo "(Or pass it directly: TEAM_ID=YOURTEAMID ./scripts/install-on-iphone.sh)"
  exit 1
fi
say "Signing with team $TEAM_ID"

# 2. Find the connected iPhone.
JSON=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
DEVICE=$(/usr/bin/python3 - "$JSON" <<'PY'
import json, sys
try: devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception: devices = []
for d in devices:
    hw, props = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hw.get("platform") == "iOS" and props.get("tunnelState") != "unavailable":
        print(d["identifier"]); break
PY
)
rm -f "$JSON"
if [ -z "$DEVICE" ]; then
  echo "No iPhone found. Plug it in with a cable, unlock it, tap Trust, and turn on Developer Mode"
  echo "(Settings > Privacy & Security > Developer Mode), then run this again."
  exit 1
fi
say "Found iPhone $DEVICE"

# 3. Build and sign (Xcode creates the certificate and profile automatically).
say "Building (first build takes a few minutes)"
xcodebuild -project BigHeadParty.xcodeproj -scheme BigHeadParty -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath build/iphone \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic \
  build | grep -E "error:|warning: .*(sign|provision)|BUILD (SUCCEEDED|FAILED)" || true
APP=build/iphone/Build/Products/Release-iphoneos/BigHeadParty.app
[ -d "$APP" ] || { echo "The build failed. Scroll up for the error, or open BigHeadParty.xcodeproj in Xcode and press Run."; exit 1; }

# 4. Install and launch.
say "Installing on your iPhone"
xcrun devicectl device install app --device "$DEVICE" "$APP"
say "Launching Big Head Party"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE" || \
  echo "Installed! If it doesn't open: on the iPhone go to Settings > General > VPN & Device Management and trust your developer profile, then tap the app."
