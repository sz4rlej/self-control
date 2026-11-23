#!/bin/zsh
# Buduje i instaluje demona (root, launchd) oraz aplikację w pasku menu.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)
LABEL=pl.softmasters.selfcontrold
PLIST=/Library/LaunchDaemons/$LABEL.plist
APP=/Applications/Self-Control.app

echo "→ demon (wymaga sudo)"
sudo install -d -o root -g wheel /usr/local/libexec "/Library/Application Support/SelfControl"
sudo install -m 755 -o root -g wheel "$BIN/selfcontrold" /usr/local/libexec/selfcontrold
sudo install -m 644 -o root -g wheel launchd/$LABEL.plist $PLIST
mkdir -p /Users/Shared/SelfControl
sudo launchctl bootout system/$LABEL 2>/dev/null || true
sudo launchctl bootstrap system $PLIST

echo "→ certyfikat strony blokady"
CA="/Library/Application Support/SelfControl/tls/ca.crt"
for i in {1..20}; do sudo test -f "$CA" && break; sleep 0.5; done
if ! security find-certificate -c "Self-Control Local CA" /Library/Keychains/System.keychain >/dev/null 2>&1; then
  sudo cat "$CA" > /tmp/selfcontrol-ca.crt
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/selfcontrol-ca.crt
  rm -f /tmp/selfcontrol-ca.crt
fi

echo "→ aplikacja"
pkill -x SelfControlApp 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/SelfControlApp" "$APP/Contents/MacOS/"
cp launchd/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
open "$APP"
echo "Gotowe. Kłódka jest w pasku menu."
