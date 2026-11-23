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

echo "→ aplikacja"
pkill -x SelfControlApp 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/SelfControlApp" "$APP/Contents/MacOS/"
cp launchd/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
open "$APP"
echo "Gotowe. Kłódka jest w pasku menu."
