#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

APP_NAME="${APP_NAME:-Syntic}"
BINARY_NAME="${BINARY_NAME:-SynticApp}"
BUNDLE_ID="${BUNDLE_ID:-com.syntic.app}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

INFO_PLIST_TEMPLATE="${REPO_ROOT}/apps/macos/Packaging/Info.plist"
ENTITLEMENTS_PLIST="${REPO_ROOT}/apps/macos/Packaging/SynticRelease.entitlements"

DIST_DIR="${REPO_ROOT}/dist/macos"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
APP_CONTENTS="${APP_BUNDLE}/Contents"
APP_MACOS="${APP_CONTENTS}/MacOS"
APP_PLIST="${APP_CONTENTS}/Info.plist"
ZIP_PATH="${DIST_DIR}/${APP_NAME}.zip"

SWIFT_BUILD_PATH="${REPO_ROOT}/apps/macos/.build/release/${BINARY_NAME}"

if [[ ! -f "${INFO_PLIST_TEMPLATE}" ]]; then
  echo "error: missing ${INFO_PLIST_TEMPLATE}"
  exit 1
fi

if [[ ! -f "${ENTITLEMENTS_PLIST}" ]]; then
  echo "error: missing ${ENTITLEMENTS_PLIST}"
  exit 1
fi

echo "==> Build Rust FFI (release)"
"${REPO_ROOT}/scripts/build-ffi.sh" release

echo "==> Build Swift shell (release)"
swift build --configuration release --package-path "${REPO_ROOT}/apps/macos"

if [[ ! -x "${SWIFT_BUILD_PATH}" ]]; then
  echo "error: missing executable ${SWIFT_BUILD_PATH}"
  exit 1
fi

echo "==> Assemble app bundle"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_MACOS}"
cp "${SWIFT_BUILD_PATH}" "${APP_MACOS}/${BINARY_NAME}"
cp "${INFO_PLIST_TEMPLATE}" "${APP_PLIST}"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${BINARY_NAME}" "${APP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${APP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_PLIST}"

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  echo "error: CODESIGN_IDENTITY is required"
  echo "hint: export CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'"
  exit 1
fi

echo "==> Sign app bundle with hardened runtime"
codesign \
  --force \
  --timestamp \
  --options runtime \
  --entitlements "${ENTITLEMENTS_PLIST}" \
  --sign "${CODESIGN_IDENTITY}" \
  "${APP_BUNDLE}"

echo "==> Verify signature and Gatekeeper assessment"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
spctl --assess --type execute --verbose=4 "${APP_BUNDLE}"

echo "==> Zip artifact"
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

if [[ "${SKIP_NOTARIZATION:-0}" == "1" ]]; then
  echo "==> Notarization skipped (SKIP_NOTARIZATION=1)"
  echo "artifact: ${APP_BUNDLE}"
  echo "artifact: ${ZIP_PATH}"
  exit 0
fi

if [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
  echo "error: NOTARYTOOL_PROFILE is required unless SKIP_NOTARIZATION=1"
  exit 1
fi

echo "==> Submit for notarization"
xcrun notarytool submit "${ZIP_PATH}" \
  --keychain-profile "${NOTARYTOOL_PROFILE}" \
  --wait

echo "==> Staple notarization ticket"
xcrun stapler staple "${APP_BUNDLE}"

echo "==> Final assessment"
spctl --assess --type execute --verbose=4 "${APP_BUNDLE}"
echo "done: ${APP_BUNDLE}"
