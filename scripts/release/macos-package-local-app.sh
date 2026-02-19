#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

APP_NAME="${APP_NAME:-SynticLocal}"
BINARY_NAME="${BINARY_NAME:-SynticApp}"
BUNDLE_ID="${BUNDLE_ID:-com.syntic.app.local}"
VERSION="${VERSION:-0.1.0-local}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

INFO_PLIST_TEMPLATE="${REPO_ROOT}/apps/macos/Packaging/Info.plist"
DIST_DIR="${REPO_ROOT}/dist/macos-local"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
APP_CONTENTS="${APP_BUNDLE}/Contents"
APP_MACOS="${APP_CONTENTS}/MacOS"
APP_PLIST="${APP_CONTENTS}/Info.plist"

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
require_cmd swift
require_cmd cargo
require_cmd codesign
require_cmd security

/bin/echo "==> Resolve code signing identity"
SELECTED_IDENTITY="${CODESIGN_IDENTITY}"
if [[ -z "${SELECTED_IDENTITY}" ]]; then
  SELECTED_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)"/\1/p' | head -n 1 || true)"
fi

if [[ -z "${SELECTED_IDENTITY}" ]]; then
  SELECTED_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)"/\1/p' | head -n 1 || true)"
fi

if [[ -n "${SELECTED_IDENTITY}" ]]; then
  echo "Using signing identity: ${SELECTED_IDENTITY}"
else
  echo "warning: no stable signing identity found; falling back to ad-hoc signing."
  echo "warning: Accessibility/Input permissions may reset after rebuilds when using ad-hoc signing."
fi

echo "==> Build Rust FFI (debug)"
"${REPO_ROOT}/scripts/build-ffi.sh"

echo "==> Build Swift shell (debug)"
swift build --package-path "${REPO_ROOT}/apps/macos"
SWIFT_BIN_PATH="$(swift build --package-path "${REPO_ROOT}/apps/macos" --show-bin-path)"
SWIFT_BUILD_PATH="${SWIFT_BIN_PATH}/${BINARY_NAME}"

if [[ ! -x "${SWIFT_BUILD_PATH}" ]]; then
  echo "error: missing executable ${SWIFT_BUILD_PATH}"
  exit 1
fi

echo "==> Assemble local app bundle"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_MACOS}"
cp "${SWIFT_BUILD_PATH}" "${APP_MACOS}/${BINARY_NAME}"
cp "${INFO_PLIST_TEMPLATE}" "${APP_PLIST}"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${BINARY_NAME}" "${APP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${APP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_PLIST}"

if [[ -n "${SELECTED_IDENTITY}" ]]; then
  echo "==> Sign local app bundle with stable identity"
  codesign --force --deep --sign "${SELECTED_IDENTITY}" "${APP_BUNDLE}"
else
  echo "==> Ad-hoc sign local app bundle"
  codesign --force --deep --sign - "${APP_BUNDLE}"
fi

echo "done: ${APP_BUNDLE}"
echo "hint: open \"${APP_BUNDLE}\""
