#!/bin/bash
# Builds roxy++.app from source. Needs only the Xcode Command Line Tools:  xcode-select --install
#
#   ./build.sh            build roxy++.app in this folder
#   ./build.sh install    build and copy to /Applications (falls back to ~/Applications)
set -euo pipefail
cd "$(dirname "$0")"

APP="roxy++.app"

# SwiftPM caches absolute paths in .build — if this folder was moved or renamed, start clean.
if [ -d .build ] && [ "$(cat .build/.macpad-path 2>/dev/null)" != "$(pwd)" ]; then
  echo "▸ Folder moved/renamed since last build — clearing old build cache…"
  rm -rf .build
fi
mkdir -p .build && pwd > .build/.macpad-path
VERSION="${VERSION:-1.0}"
SWIFT_ARGS=(-c release)
# UNIVERSAL=1 builds for Apple Silicon + Intel (needs the full Xcode app, not just Command Line Tools)
if [ "${UNIVERSAL:-0}" = "1" ]; then
  SWIFT_ARGS+=(--arch arm64 --arch x86_64)
fi
echo "▸ Compiling (release)…"
swift build "${SWIFT_ARGS[@]}"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)/MacPad"

echo "▸ Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/MacPad"

# App icon (PNG -> icns) using built-in macOS tools
if [ -f Resources/AppIcon.png ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "${ICONSET}"
  for s in 16 32 128 256 512; do
    sips -z ${s} ${s} Resources/AppIcon.png --out "${ICONSET}/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "${ICONSET}/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "${ICONSET}" -o "${APP}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>roxy++</string>
  <key>CFBundleDisplayName</key><string>roxy++</string>
  <key>CFBundleIdentifier</key><string>local.macpad.editor</string>
  <key>CFBundleExecutable</key><string>MacPad</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>__VERSION__</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Text Document</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.text</string>
        <string>public.plain-text</string>
        <string>public.source-code</string>
        <string>public.script</string>
        <string>public.json</string>
        <string>public.xml</string>
        <string>public.yaml</string>
        <string>public.comma-separated-values-text</string>
        <string>public.log</string>
        <string>net.daringfireball.markdown</string>
        <string>public.data</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

sed -i '' "s/__VERSION__/${VERSION}/" "${APP}/Contents/Info.plist"

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || echo "  (codesign skipped)"

if [ "${1:-}" = "install" ]; then
  DEST="/Applications"
  [ -w "${DEST}" ] || DEST="${HOME}/Applications"
  mkdir -p "${DEST}"
  rm -rf "${DEST}/${APP}"
  cp -R "${APP}" "${DEST}/"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${DEST}/${APP}" >/dev/null 2>&1 || true
  echo "✓ Installed to ${DEST}/${APP}"
else
  echo "✓ Built $(pwd)/${APP}  —  run:  open ${APP}"
fi
