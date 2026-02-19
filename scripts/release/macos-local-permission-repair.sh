#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-com.syntic.app.local}"
APP_PATH="${APP_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/dist/macos-local/SynticLocal.app}"

echo "==> Reset TCC permissions for ${BUNDLE_ID}"
tccutil reset Accessibility "${BUNDLE_ID}" || true
tccutil reset ListenEvent "${BUNDLE_ID}" || true
tccutil reset Microphone "${BUNDLE_ID}" || true
tccutil reset SpeechRecognition "${BUNDLE_ID}" || true

echo "==> Open System Settings permission panes"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"

if [[ -d "${APP_PATH}" ]]; then
  echo "==> Open app bundle location"
  open -R "${APP_PATH}"
fi

echo "done: enable ${BUNDLE_ID} in all opened privacy panes, then restart the app."
