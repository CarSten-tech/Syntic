#!/usr/bin/env bash
set -euo pipefail

LABEL=""
APPEND_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)
      LABEL="${2:-}"
      shift 2
      ;;
    --append)
      APPEND_FILE="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 --label \"Case Name\" [--append path/to/file.md]" >&2
      exit 2
      ;;
  esac
done

if [[ -z "${LABEL}" ]]; then
  echo "Missing required argument --label" >&2
  echo "Usage: $0 --label \"Case Name\" [--append path/to/file.md]" >&2
  exit 2
fi

SCRIPT_OUTPUT="$(osascript <<'APPLESCRIPT'
set finderRunning to false
set finderFrontmost to false
set finderWindowCount to 0
set finderView to "none"
set selectedCount to 0
set selectedPaths to ""

try
  tell application "System Events"
    set finderRunning to (exists process "Finder")
    if finderRunning then
      set finderFrontmost to frontmost of process "Finder"
    end if
  end tell

  if finderRunning then
    tell application "Finder"
      set finderWindowCount to count of windows
      if finderWindowCount > 0 then
        set finderView to (current view of front window) as string
      end if
      set selectedCount to count of selection
      if selectedCount > 0 then
        set pathList to {}
        repeat with selectedItem in selection
          set end of pathList to POSIX path of (selectedItem as alias)
        end repeat
        set AppleScript's text item delimiters to linefeed
        set selectedPaths to pathList as string
        set AppleScript's text item delimiters to ""
      end if
    end tell
  end if
on error errMsg number errNum
  return "error" & tab & errNum & tab & errMsg & tab & "false" & tab & "false" & tab & "0" & tab & "none" & tab & "0" & tab & ""
end try

return "ok" & tab & "0" & tab & "-" & tab & (finderRunning as string) & tab & (finderFrontmost as string) & tab & (finderWindowCount as string) & tab & finderView & tab & (selectedCount as string) & tab & selectedPaths
APPLESCRIPT
)"

IFS=$'\t' read -r RESULT ERR_NUM ERR_MSG FINDER_RUNNING FINDER_FRONTMOST WINDOW_COUNT VIEW_NAME SELECTED_COUNT SELECTED_PATHS <<< "${SCRIPT_OUTPUT}"

STATUS="ok"
NOTES=""
ERR_MSG="${ERR_MSG//$'\n'/ }"
ERR_MSG="${ERR_MSG//$'\t'/ }"

if [[ "${RESULT}" != "ok" ]]; then
  STATUS="error"
  NOTES="osascript error ${ERR_NUM}: ${ERR_MSG}"
elif [[ "${FINDER_RUNNING}" != "true" ]]; then
  STATUS="finder-not-running"
elif [[ "${SELECTED_COUNT}" == "0" ]]; then
  STATUS="empty-selection"
else
  STATUS="ok"
  NOTES="${SELECTED_PATHS//$'\n'/; }"
fi

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
ROW="| ${TIMESTAMP} | ${LABEL} | ${FINDER_RUNNING} | ${FINDER_FRONTMOST} | ${WINDOW_COUNT} | ${VIEW_NAME} | ${SELECTED_COUNT} | ${STATUS} | ${NOTES} |"

echo "${ROW}"

if [[ -n "${APPEND_FILE}" ]]; then
  printf '%s\n' "${ROW}" >> "${APPEND_FILE}"
  echo "Appended row to ${APPEND_FILE}"
fi
