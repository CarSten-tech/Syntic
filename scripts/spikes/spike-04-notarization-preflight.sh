#!/usr/bin/env bash
set -euo pipefail

check_binary() {
  local bin_name="$1"
  if command -v "${bin_name}" >/dev/null 2>&1; then
    echo "ok|${bin_name}|$(command -v "${bin_name}")"
  else
    echo "fail|${bin_name}|missing"
  fi
}

XCODE_PATH="$(xcode-select -p 2>/dev/null || true)"
if [[ -n "${XCODE_PATH}" ]]; then
  echo "ok|xcode-select|${XCODE_PATH}"
else
  echo "fail|xcode-select|not configured"
fi

check_binary codesign
check_binary xcrun
check_binary security

NOTARYTOOL_PATH=""
if command -v xcrun >/dev/null 2>&1; then
  NOTARYTOOL_PATH="$(xcrun --find notarytool 2>/dev/null || true)"
fi

if [[ -n "${NOTARYTOOL_PATH}" ]]; then
  echo "ok|notarytool|${NOTARYTOOL_PATH}"
else
  echo "fail|notarytool|xcrun could not find notarytool"
fi

IDENTITIES_RAW="$(security find-identity -v -p codesigning 2>/dev/null || true)"
IDENTITY_COUNT="$(echo "${IDENTITIES_RAW}" | rg -c "Developer ID|Apple Development|Apple Distribution" || true)"

if [[ -n "${IDENTITY_COUNT}" ]] && (( IDENTITY_COUNT > 0 )); then
  echo "ok|codesign-identities|${IDENTITY_COUNT} matching identities"
else
  echo "fail|codesign-identities|no matching identity found"
fi
