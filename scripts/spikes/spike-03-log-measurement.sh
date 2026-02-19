#!/usr/bin/env bash
set -euo pipefail

PROVIDER=""
SECONDS=""
LOCALE=""
NOISE=""
FIRST_LATENCY_MS=""
FINAL_LATENCY_MS=""
QUALITY=""
NOTES=""
APPEND_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --seconds)
      SECONDS="${2:-}"
      shift 2
      ;;
    --locale)
      LOCALE="${2:-}"
      shift 2
      ;;
    --noise)
      NOISE="${2:-}"
      shift 2
      ;;
    --first-latency-ms)
      FIRST_LATENCY_MS="${2:-}"
      shift 2
      ;;
    --final-latency-ms)
      FINAL_LATENCY_MS="${2:-}"
      shift 2
      ;;
    --quality)
      QUALITY="${2:-}"
      shift 2
      ;;
    --notes)
      NOTES="${2:-}"
      shift 2
      ;;
    --append)
      APPEND_FILE="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for required in PROVIDER SECONDS LOCALE NOISE FIRST_LATENCY_MS FINAL_LATENCY_MS QUALITY; do
  if [[ -z "${!required}" ]]; then
    echo "Missing required argument for ${required}" >&2
    exit 2
  fi
done

if ! [[ "${SECONDS}" =~ ^[0-9]+$ ]]; then
  echo "--seconds must be an integer" >&2
  exit 2
fi

for metric in FIRST_LATENCY_MS FINAL_LATENCY_MS QUALITY; do
  if ! [[ "${!metric}" =~ ^[0-9]+$ ]]; then
    echo "${metric} must be an integer" >&2
    exit 2
  fi
done

if (( QUALITY < 1 || QUALITY > 5 )); then
  echo "--quality must be between 1 and 5" >&2
  exit 2
fi

NOTES="${NOTES//|//}"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
ROW="| ${TIMESTAMP} | ${PROVIDER} | ${SECONDS} | ${LOCALE} | ${NOISE} | ${FIRST_LATENCY_MS} | ${FINAL_LATENCY_MS} | ${QUALITY} | ${NOTES} |"

echo "${ROW}"

if [[ -n "${APPEND_FILE}" ]]; then
  printf '%s\n' "${ROW}" >> "${APPEND_FILE}"
  echo "Appended row to ${APPEND_FILE}"
fi
