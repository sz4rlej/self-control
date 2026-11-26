#!/bin/zsh
# Buduje build/Self-Control-<wersja>.dmg z instalatorem .pkg i skryptem odinstalowania.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" launchd/Info.plist)
OUT=build
WORK=$OUT/dmg-work
rm -rf $WORK && mkdir -p $WORK/root/Applications $WORK/root/usr/local/libexec $WORK/root/Library/LaunchDaemons $WORK/scripts $WORK/dmg

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

APP=$WORK/root/Applications/Self-Control.app
mkdir -p $APP/Contents/MacOS
cp $BIN/SelfControlApp $APP/Contents/MacOS/
cp launchd/Info.plist $APP/Contents/
codesign --force --sign - $APP
cp $BIN/selfcontrold $WORK/root/usr/local/libexec/
codesign --force --sign - --identifier pl.softmasters.selfcontrold $WORK/root/usr/local/libexec/selfcontrold
cp launchd/pl.softmasters.selfcontrold.plist $WORK/root/Library/LaunchDaemons/
cp scripts/pkg/preinstall scripts/pkg/postinstall $WORK/scripts/

xattr -cr $WORK/root
export COPYFILE_DISABLE=1
pkgbuild --analyze --root $WORK/root $WORK/components.plist >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO $WORK/components.plist
pkgbuild --root $WORK/root --component-plist $WORK/components.plist --scripts $WORK/scripts \
  --identifier pl.softmasters.selfcontrol --version $VERSION \
  --install-location / $WORK/component.pkg
productbuild --package $WORK/component.pkg "$WORK/dmg/Zainstaluj Self-Control.pkg"

cp scripts/uninstall.sh "$WORK/dmg/Odinstaluj.command"
chmod 755 "$WORK/dmg/Odinstaluj.command"

DMG=$OUT/Self-Control-$VERSION.dmg
rm -f $DMG
hdiutil create -volname "Self-Control $VERSION" -srcfolder $WORK/dmg -ov -format UDZO $DMG >/dev/null
rm -rf $WORK
echo "Gotowe: $DMG"
