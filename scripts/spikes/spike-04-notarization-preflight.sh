#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

INFO_PLIST="${REPO_ROOT}/apps/macos/Packaging/Info.plist"
ENTITLEMENTS_PLIST="${REPO_ROOT}/apps/macos/Packaging/SynticRelease.entitlements"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
REQUIRE_NOTARY_AUTH="${REQUIRE_NOTARY_AUTH:-0}"
NOTARY_AUTH_MODE="${NOTARY_AUTH_MODE:-auto}"

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

check_executable_file() {
  local path="$1"
  local name="$2"
  if [[ -x "${path}" ]]; then
    print_result "ok" "${name}" "${path}"
  else
    print_result "fail" "${name}" "missing executable at ${path}"
  fi
}

check_regular_file() {
  local path="$1"
  local check_name="$2"
  if [[ -f "${path}" ]]; then
    print_result "ok" "${check_name}" "${path}"
  else
    print_result "fail" "${check_name}" "missing file: ${path}"
  fi
}

check_plist_lint() {
  local plist_path="$1"
  local check_name="$2"
  if plutil -lint "${plist_path}" >/dev/null 2>&1; then
    print_result "ok" "${check_name}" "valid plist"
  else
    print_result "fail" "${check_name}" "invalid plist: ${plist_path}"
  fi
}

check_plist_key() {
  local plist_path="$1"
  local key_path="$2"
  local check_name="$3"
  if "${PLIST_BUDDY}" -c "Print ${key_path}" "${plist_path}" >/dev/null 2>&1; then
    local value
    value="$("${PLIST_BUDDY}" -c "Print ${key_path}" "${plist_path}" 2>/dev/null || true)"
    print_result "ok" "${check_name}" "${value}"
  else
    print_result "fail" "${check_name}" "missing key ${key_path} in $(basename "${plist_path}")"
  fi
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  print_result "ok" "platform" "darwin"
else
  print_result "fail" "platform" "non-macos host detected"
fi

XCODE_PATH="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "${XCODE_PATH}" ]]; then
  print_result "fail" "xcode-select" "not configured"
elif [[ "${XCODE_PATH}" == *"/CommandLineTools" ]]; then
  print_result "fail" "xcode-select" "${XCODE_PATH} (CommandLineTools active, full Xcode required)"
elif [[ ! -d "${XCODE_PATH}" ]]; then
  print_result "fail" "xcode-select" "${XCODE_PATH} (directory missing)"
else
  print_result "ok" "xcode-select" "${XCODE_PATH}"
fi

check_binary codesign
check_binary xcodebuild
check_binary xcrun
check_binary security
check_binary plutil
check_executable_file "${PLIST_BUDDY}" "plistbuddy"

SDK_PLATFORM_PATH="$(xcrun --sdk macosx --show-sdk-platform-path 2>/dev/null || true)"
if [[ -n "${SDK_PLATFORM_PATH}" ]]; then
  print_result "ok" "sdk-platform-path" "${SDK_PLATFORM_PATH}"
else
  print_result "fail" "sdk-platform-path" "xcrun --sdk macosx --show-sdk-platform-path failed"
fi

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
  check_plist_lint "${INFO_PLIST}" "info-plist-lint"
  check_plist_key "${INFO_PLIST}" ":CFBundleIdentifier" "info-cfbundleidentifier"
  check_plist_key "${INFO_PLIST}" ":NSMicrophoneUsageDescription" "info-microphone-usage"
  check_plist_key "${INFO_PLIST}" ":NSAppleEventsUsageDescription" "info-appleevents-usage"
  BUNDLE_ID="$("${PLIST_BUDDY}" -c "Print :CFBundleIdentifier" "${INFO_PLIST}" 2>/dev/null || true)"
  if [[ "${BUNDLE_ID}" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
    print_result "ok" "info-bundle-id-format" "${BUNDLE_ID}"
  else
    print_result "fail" "info-bundle-id-format" "invalid bundle id format '${BUNDLE_ID}'"
  fi
else
  print_result "fail" "info-plist" "missing ${INFO_PLIST}"
fi

if [[ -f "${ENTITLEMENTS_PLIST}" ]]; then
  print_result "ok" "entitlements-plist" "${ENTITLEMENTS_PLIST}"
  check_plist_lint "${ENTITLEMENTS_PLIST}" "entitlements-plist-lint"
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

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  if echo "${IDENTITIES_RAW}" | grep -F -- "${CODESIGN_IDENTITY}" >/dev/null 2>&1; then
    print_result "ok" "codesign-identity-selected" "${CODESIGN_IDENTITY}"
  else
    print_result "fail" "codesign-identity-selected" "CODESIGN_IDENTITY not found in keychain identities"
  fi
else
  print_result "ok" "codesign-identity-selected" "CODESIGN_IDENTITY not set (selection skipped)"
fi

has_profile_auth() {
  [[ -n "${NOTARYTOOL_PROFILE:-}" ]]
}

has_api_key_auth() {
  [[ -n "${NOTARY_API_KEY_PATH:-}" ]] || [[ -n "${NOTARY_API_KEY_ID:-}" ]] || [[ -n "${NOTARY_ISSUER_ID:-}" ]]
}

selected_auth_mode=""
case "${NOTARY_AUTH_MODE}" in
  auto)
    if has_profile_auth; then
      selected_auth_mode="profile"
    elif has_api_key_auth; then
      selected_auth_mode="api_key"
    else
      selected_auth_mode="none"
    fi
    ;;
  profile|api_key)
    selected_auth_mode="${NOTARY_AUTH_MODE}"
    ;;
  *)
    selected_auth_mode="invalid"
    ;;
esac

if [[ "${selected_auth_mode}" == "invalid" ]]; then
  print_result "fail" "notary-auth-mode" "invalid NOTARY_AUTH_MODE='${NOTARY_AUTH_MODE}' (expected auto|profile|api_key)"
elif [[ "${selected_auth_mode}" == "none" ]]; then
  if [[ "${REQUIRE_NOTARY_AUTH}" == "1" ]]; then
    print_result "fail" "notary-auth-mode" "required but no notary auth configured"
  else
    print_result "ok" "notary-auth-mode" "none (optional)"
  fi
else
  print_result "ok" "notary-auth-mode" "${selected_auth_mode}"
fi

if [[ "${selected_auth_mode}" == "profile" ]]; then
  if [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
    print_result "fail" "notarytool-profile" "NOTARYTOOL_PROFILE is required for profile mode"
  elif xcrun notarytool history --keychain-profile "${NOTARYTOOL_PROFILE}" >/dev/null 2>&1; then
    print_result "ok" "notarytool-profile" "${NOTARYTOOL_PROFILE}"
  else
    print_result "fail" "notarytool-profile" "profile '${NOTARYTOOL_PROFILE}' invalid or inaccessible"
  fi
elif [[ "${selected_auth_mode}" == "api_key" ]]; then
  if [[ -z "${NOTARY_API_KEY_PATH:-}" ]]; then
    print_result "fail" "notary-api-key-path" "NOTARY_API_KEY_PATH missing"
  else
    check_regular_file "${NOTARY_API_KEY_PATH}" "notary-api-key-path"
  fi

  if [[ -z "${NOTARY_API_KEY_ID:-}" ]]; then
    print_result "fail" "notary-api-key-id" "NOTARY_API_KEY_ID missing"
  elif [[ "${NOTARY_API_KEY_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
    print_result "ok" "notary-api-key-id" "${NOTARY_API_KEY_ID}"
  else
    print_result "fail" "notary-api-key-id" "unexpected key id format '${NOTARY_API_KEY_ID}'"
  fi

  if [[ -z "${NOTARY_ISSUER_ID:-}" ]]; then
    print_result "fail" "notary-issuer-id" "NOTARY_ISSUER_ID missing"
  elif [[ "${NOTARY_ISSUER_ID}" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    print_result "ok" "notary-issuer-id" "${NOTARY_ISSUER_ID}"
  else
    print_result "fail" "notary-issuer-id" "unexpected issuer id format '${NOTARY_ISSUER_ID}'"
  fi
fi

if (( FAIL_COUNT == 0 )); then
  echo "summary|result|pass"
  exit 0
fi

echo "summary|result|fail (${FAIL_COUNT} checks failed)"
exit 1
