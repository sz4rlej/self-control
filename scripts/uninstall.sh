#!/bin/zsh
# Usuwa demona i aplikację — tylko gdy nie trwa blokada.
set -euo pipefail
STATE="/Library/Application Support/SelfControl/state.json"
if [[ -f "$STATE" ]] && grep -q '"blocking" : true' "$STATE"; then
  echo "Trwa blokada — odinstalowanie możliwe po jej zakończeniu."; exit 1
fi
LABEL=pl.softmasters.selfcontrold
pkill -x SelfControlApp 2>/dev/null || true
sudo launchctl bootout system/$LABEL 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/$LABEL.plist /usr/local/libexec/selfcontrold
sudo rm -rf "/Library/Application Support/SelfControl" /Applications/Self-Control.app
echo "Odinstalowano."
