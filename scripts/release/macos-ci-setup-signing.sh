#!/usr/bin/env bash
set -euo pipefail

KEYCHAIN_NAME="${CI_KEYCHAIN_NAME:-syntic-ci.keychain-db}"
KEYCHAIN_PATH="${CI_KEYCHAIN_PATH:-${HOME}/Library/Keychains/${KEYCHAIN_NAME}}"
CERT_P12_B64="${APPLE_CERT_P12_BASE64:-}"
CERT_P12_PASSWORD="${APPLE_CERT_PASSWORD:-}"
KEYCHAIN_PASSWORD="${CI_KEYCHAIN_PASSWORD:-}"

if [[ -z "${CERT_P12_B64}" ]]; then
  echo "error: APPLE_CERT_P12_BASE64 is required"
  exit 1
fi

if [[ -z "${CERT_P12_PASSWORD}" ]]; then
  echo "error: APPLE_CERT_PASSWORD is required"
  exit 1
fi

if [[ -z "${KEYCHAIN_PASSWORD}" ]]; then
  echo "error: CI_KEYCHAIN_PASSWORD is required"
  exit 1
fi

CERT_P12_FILE="$(mktemp -t syntic-cert.XXXXXX.p12)"
cleanup_temp_files() {
  rm -f "${CERT_P12_FILE}"
}
trap cleanup_temp_files EXIT

echo "==> Decode signing certificate"
printf '%s' "${CERT_P12_B64}" | base64 -D >"${CERT_P12_FILE}"

if [[ ! -s "${CERT_P12_FILE}" ]]; then
  echo "error: decoded certificate file is empty"
  exit 1
fi

echo "==> Create and unlock CI keychain"
security delete-keychain "${KEYCHAIN_PATH}" >/dev/null 2>&1 || true
security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security list-keychains -d user -s "${KEYCHAIN_PATH}" login.keychain-db
security default-keychain -d user -s "${KEYCHAIN_PATH}"

echo "==> Import Developer ID certificate into keychain"
security import "${CERT_P12_FILE}" \
  -k "${KEYCHAIN_PATH}" \
  -P "${CERT_P12_PASSWORD}" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "${KEYCHAIN_PASSWORD}" \
  "${KEYCHAIN_PATH}"

IDENTITY_LINE="$(security find-identity -v -p codesigning "${KEYCHAIN_PATH}" | grep "Developer ID Application:" | head -n 1 || true)"
if [[ -z "${IDENTITY_LINE}" ]]; then
  echo "error: no 'Developer ID Application' identity found in ${KEYCHAIN_PATH}"
  security find-identity -v -p codesigning "${KEYCHAIN_PATH}" || true
  exit 1
fi

CODESIGN_IDENTITY="$(echo "${IDENTITY_LINE}" | sed -E 's/.*"([^"]+)".*/\1/')"
if [[ -z "${CODESIGN_IDENTITY}" ]]; then
  echo "error: failed to parse CODESIGN identity from keychain output"
  exit 1
fi

echo "==> Selected identity: ${CODESIGN_IDENTITY}"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "codesign_identity=${CODESIGN_IDENTITY}"
    echo "ci_keychain_path=${KEYCHAIN_PATH}"
  } >>"${GITHUB_OUTPUT}"
fi
