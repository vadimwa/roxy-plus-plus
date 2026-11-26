#!/bin/bash
# Creates installers for roxy++ in ./dist:
#   roxy++-<version>.dmg   drag-to-Applications disk image
#   roxy++-<version>.pkg   double-click installer (installs into /Applications)
#
# Usage:
#   bash make-installer.sh
#
# Optional settings (environment variables):
#   VERSION=1.2                 version number shown in Finder / About box (default 1.0)
#   UNIVERSAL=1                 build for Apple Silicon + Intel (needs the full Xcode app)
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"   sign the app for distribution
#   INSTALLER_ID="Developer ID Installer: Your Name (TEAMID)"     sign the .pkg
#   NOTARY_PROFILE=macpad       notarize with Apple (profile made with: xcrun notarytool store-credentials)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0}"
APP="roxy++.app"
DIST="dist"
DMG="${DIST}/roxy++-${VERSION}.dmg"
PKG="${DIST}/roxy++-${VERSION}.pkg"
export VERSION

echo "▸ Building ${APP} ${VERSION}…"
bash build.sh

# Optional: proper signing for distribution to other Macs
if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "▸ Signing with ${DEVELOPER_ID}…"
  codesign --force --deep --options runtime --timestamp --sign "${DEVELOPER_ID}" "${APP}"
  codesign --verify --strict --verbose=1 "${APP}"
fi

rm -rf "${DIST}"
mkdir -p "${DIST}"

# ---------- DMG ----------
echo "▸ Creating disk image…"
STAGE="$(mktemp -d)"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
cat > "${STAGE}/Install roxy++.txt" <<TXT
To install roxy++: drag roxy++ onto the Applications folder.

First launch on a Mac other than the one it was built on:
right-click roxy++ in Applications ▸ Open ▸ Open
(or run:  xattr -cr /Applications/roxy++.app )
TXT
hdiutil create -volname "roxy++ ${VERSION}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}" >/dev/null
rm -rf "${STAGE}"
if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --timestamp --sign "${DEVELOPER_ID}" "${DMG}"
fi

# ---------- PKG ----------
echo "▸ Creating .pkg installer…"
PKGROOT="$(mktemp -d)"
mkdir -p "${PKGROOT}/Applications"
cp -R "${APP}" "${PKGROOT}/Applications/"
COMPONENT_PLIST="$(mktemp -d)/components.plist"
pkgbuild --analyze --root "${PKGROOT}" "${COMPONENT_PLIST}" >/dev/null
# Always install to /Applications (don't "upgrade" a copy found elsewhere on disk)
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "${COMPONENT_PLIST}"
COMPONENT_PKG="$(mktemp -d)/roxy++-component.pkg"
pkgbuild --root "${PKGROOT}" --component-plist "${COMPONENT_PLIST}" \
  --identifier local.macpad.editor --version "${VERSION}" --install-location / \
  "${COMPONENT_PKG}" >/dev/null
if [ -n "${INSTALLER_ID:-}" ]; then
  productbuild --package "${COMPONENT_PKG}" --sign "${INSTALLER_ID}" "${PKG}" >/dev/null
else
  productbuild --package "${COMPONENT_PKG}" "${PKG}" >/dev/null
fi
rm -rf "${PKGROOT}"

# ---------- Optional notarization ----------
if [ -n "${NOTARY_PROFILE:-}" ]; then
  for f in "${DMG}" "${PKG}"; do
    echo "▸ Notarizing $(basename "${f}") (takes a few minutes)…"
    xcrun notarytool submit "${f}" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "${f}"
  done
fi

echo ""
echo "✓ Installers ready:"
echo "    $(pwd)/${DMG}"
echo "    $(pwd)/${PKG}"
if [ -z "${DEVELOPER_ID:-}" ]; then
  echo ""
  echo "  These are unsigned (fine for your own Macs). On another Mac, open roxy++ the first"
  echo "  time with right-click ▸ Open, or run: xattr -cr /Applications/roxy++.app"
fi
open "${DIST}" 2>/dev/null || true
