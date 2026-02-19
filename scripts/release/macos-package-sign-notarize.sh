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
PRE_FLIGHT_SCRIPT="${REPO_ROOT}/scripts/spikes/spike-04-notarization-preflight.sh"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "error: missing ${path}"
    exit 1
  fi
}

require_cmd() {
  local bin_name="$1"
  if ! command -v "${bin_name}" >/dev/null 2>&1; then
    echo "error: required command missing: ${bin_name}"
    exit 1
  fi
}

require_file "${INFO_PLIST_TEMPLATE}"
require_file "${ENTITLEMENTS_PLIST}"
require_file "${PRE_FLIGHT_SCRIPT}"
require_cmd swift
require_cmd xcrun
require_cmd security
require_cmd codesign
require_cmd spctl
require_cmd ditto
require_cmd plutil

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  echo "error: CODESIGN_IDENTITY is required"
  echo "hint: export CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'"
  exit 1
fi

echo "==> Preflight (signing/notarization prerequisites)"
REQUIRE_NOTARYTOOL_PROFILE=0
if [[ "${SKIP_NOTARIZATION:-0}" != "1" ]]; then
  REQUIRE_NOTARYTOOL_PROFILE=1
fi
REQUIRE_NOTARYTOOL_PROFILE="${REQUIRE_NOTARYTOOL_PROFILE}" \
  CODESIGN_IDENTITY="${CODESIGN_IDENTITY}" \
  NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}" \
  "${PRE_FLIGHT_SCRIPT}"

echo "==> Build Rust FFI (release)"
"${REPO_ROOT}/scripts/build-ffi.sh" release

echo "==> Build Swift shell (release)"
swift build --configuration release --package-path "${REPO_ROOT}/apps/macos"
SWIFT_BIN_PATH="$(swift build --configuration release --package-path "${REPO_ROOT}/apps/macos" --show-bin-path)"
SWIFT_BUILD_PATH="${SWIFT_BIN_PATH}/${BINARY_NAME}"

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
NOTARY_OUTPUT_JSON="$(mktemp -t syntic-notary-output.XXXXXX.json)"
cleanup_notary_output() {
  rm -f "${NOTARY_OUTPUT_JSON}"
}
trap cleanup_notary_output EXIT

set +e
xcrun notarytool submit "${ZIP_PATH}" \
  --keychain-profile "${NOTARYTOOL_PROFILE}" \
  --wait \
  --output-format json >"${NOTARY_OUTPUT_JSON}" 2>&1
NOTARY_SUBMIT_EXIT=$?
set -e
if (( NOTARY_SUBMIT_EXIT != 0 )); then
  echo "error: notarytool submit failed (exit ${NOTARY_SUBMIT_EXIT})"
  cat "${NOTARY_OUTPUT_JSON}"
  exit "${NOTARY_SUBMIT_EXIT}"
fi

cat "${NOTARY_OUTPUT_JSON}"

NOTARY_STATUS="$(plutil -extract status raw -o - "${NOTARY_OUTPUT_JSON}" 2>/dev/null || true)"
NOTARY_SUBMISSION_ID="$(plutil -extract id raw -o - "${NOTARY_OUTPUT_JSON}" 2>/dev/null || true)"
if [[ "${NOTARY_STATUS}" != "Accepted" ]]; then
  echo "error: notarization status is '${NOTARY_STATUS:-unknown}'"
  if [[ -n "${NOTARY_SUBMISSION_ID}" ]]; then
    echo "==> Notarization log (${NOTARY_SUBMISSION_ID})"
    xcrun notarytool log "${NOTARY_SUBMISSION_ID}" --keychain-profile "${NOTARYTOOL_PROFILE}" || true
  fi
  exit 1
fi

echo "==> Staple notarization ticket"
xcrun stapler staple "${APP_BUNDLE}"

echo "==> Final assessment"
spctl --assess --type execute --verbose=4 "${APP_BUNDLE}"
echo "done: ${APP_BUNDLE}"
