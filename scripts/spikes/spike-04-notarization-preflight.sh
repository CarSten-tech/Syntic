#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

INFO_PLIST="${REPO_ROOT}/apps/macos/Packaging/Info.plist"
ENTITLEMENTS_PLIST="${REPO_ROOT}/apps/macos/Packaging/SynticRelease.entitlements"

FAIL_COUNT=0

print_result() {
  local status="$1"
  local check_name="$2"
  local details="$3"
  echo "${status}|${check_name}|${details}"
  if [[ "${status}" == "fail" ]]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

check_binary() {
  local bin_name="$1"
  if command -v "${bin_name}" >/dev/null 2>&1; then
    print_result "ok" "${bin_name}" "$(command -v "${bin_name}")"
  else
    print_result "fail" "${bin_name}" "missing"
  fi
}

check_plist_key() {
  local plist_path="$1"
  local key_path="$2"
  local check_name="$3"
  if /usr/libexec/PlistBuddy -c "Print ${key_path}" "${plist_path}" >/dev/null 2>&1; then
    local value
    value="$(/usr/libexec/PlistBuddy -c "Print ${key_path}" "${plist_path}" 2>/dev/null || true)"
    print_result "ok" "${check_name}" "${value}"
  else
    print_result "fail" "${check_name}" "missing key ${key_path} in $(basename "${plist_path}")"
  fi
}

XCODE_PATH="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "${XCODE_PATH}" ]]; then
  print_result "fail" "xcode-select" "not configured"
elif [[ "${XCODE_PATH}" == *"/CommandLineTools" ]]; then
  print_result "fail" "xcode-select" "${XCODE_PATH} (CommandLineTools active, full Xcode required)"
else
  print_result "ok" "xcode-select" "${XCODE_PATH}"
fi

check_binary codesign
check_binary xcodebuild
check_binary xcrun
check_binary security

XCODEBUILD_VERSION="$(xcodebuild -version 2>/dev/null || true)"
if [[ -n "${XCODEBUILD_VERSION}" ]]; then
  print_result "ok" "xcodebuild-version" "$(echo "${XCODEBUILD_VERSION}" | tr '\n' '; ')"
else
  print_result "fail" "xcodebuild-version" "unavailable"
fi

NOTARYTOOL_PATH=""
if command -v xcrun >/dev/null 2>&1; then
  NOTARYTOOL_PATH="$(xcrun --find notarytool 2>/dev/null || true)"
fi
if [[ -n "${NOTARYTOOL_PATH}" ]]; then
  print_result "ok" "notarytool" "${NOTARYTOOL_PATH}"
else
  print_result "fail" "notarytool" "xcrun could not find notarytool"
fi

if [[ -f "${INFO_PLIST}" ]]; then
  print_result "ok" "info-plist" "${INFO_PLIST}"
  check_plist_key "${INFO_PLIST}" ":CFBundleIdentifier" "info-cfbundleidentifier"
  check_plist_key "${INFO_PLIST}" ":NSMicrophoneUsageDescription" "info-microphone-usage"
  check_plist_key "${INFO_PLIST}" ":NSAppleEventsUsageDescription" "info-appleevents-usage"
else
  print_result "fail" "info-plist" "missing ${INFO_PLIST}"
fi

if [[ -f "${ENTITLEMENTS_PLIST}" ]]; then
  print_result "ok" "entitlements-plist" "${ENTITLEMENTS_PLIST}"
else
  print_result "fail" "entitlements-plist" "missing ${ENTITLEMENTS_PLIST}"
fi

IDENTITIES_RAW="$(security find-identity -v -p codesigning 2>/dev/null || true)"
DEVELOPER_ID_COUNT="$(echo "${IDENTITIES_RAW}" | grep -c "Developer ID Application:" || true)"
if [[ -n "${DEVELOPER_ID_COUNT}" ]] && (( DEVELOPER_ID_COUNT > 0 )); then
  print_result "ok" "codesign-identities" "${DEVELOPER_ID_COUNT} Developer ID Application identities"
else
  print_result "fail" "codesign-identities" "no Developer ID Application identity found"
fi

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  if xcrun notarytool history --keychain-profile "${NOTARYTOOL_PROFILE}" >/dev/null 2>&1; then
    print_result "ok" "notarytool-profile" "${NOTARYTOOL_PROFILE}"
  else
    print_result "fail" "notarytool-profile" "profile '${NOTARYTOOL_PROFILE}' invalid or inaccessible"
  fi
else
  print_result "ok" "notarytool-profile" "NOTARYTOOL_PROFILE not set (skipped validation)"
fi

if (( FAIL_COUNT == 0 )); then
  echo "summary|result|pass"
  exit 0
fi

echo "summary|result|fail (${FAIL_COUNT} checks failed)"
exit 1
