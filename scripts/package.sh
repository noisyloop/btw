#!/usr/bin/env bash
# Builds dist/btw.app and dist/btw-macos.dmg: release build, optional icon from
# assets/AppIcon.png (1024x1024), ad-hoc signature with the virtualization
# entitlement. The VM disk is not inside the dmg; it comes from the distro build.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist"
app="$dist/btw.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/app/Info.plist")"

swift build -c release --arch arm64 --package-path "$root/app"
bin="$(swift build -c release --arch arm64 --package-path "$root/app" --show-bin-path)/btw"

rm -rf "$app" "$dist/btw-macos.dmg"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/btw"
cp "$root/app/Info.plist" "$app/Contents/Info.plist"

if [[ -f "$root/assets/AppIcon.png" ]]; then
  iconset="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$root/assets/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$root/assets/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
else
  echo "note: no assets/AppIcon.png, building without an icon"
fi

codesign --force --sign - --entitlements "$root/app/btw.entitlements" --options runtime "$app"
codesign --verify --strict "$app"

staging="$(mktemp -d)"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "btw $version" -srcfolder "$staging" -format UDZO -ov "$dist/btw-macos.dmg" >/dev/null
rm -rf "$staging"

echo "built $app"
echo "built $dist/btw-macos.dmg ($(du -h "$dist/btw-macos.dmg" | cut -f1))"
