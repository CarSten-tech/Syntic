#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  spike-05-e2e-smoke-check.sh mark
  spike-05-e2e-smoke-check.sh verify --since-ms <epoch_ms> --scenario <direct_injection|clipboard_fallback|stt_permission_denied> [--telemetry-log <path>] [--core-feed-log <path>]

Examples:
  MARK_MS="$(./scripts/spikes/spike-05-e2e-smoke-check.sh mark)"
  ./scripts/spikes/spike-05-e2e-smoke-check.sh verify --since-ms "${MARK_MS}" --scenario direct_injection
EOF
}

require_cmd() {
  local bin_name="$1"
  if ! command -v "${bin_name}" >/dev/null 2>&1; then
    echo "error: required command missing: ${bin_name}" >&2
    exit 1
  fi
}

COMMAND="${1:-}"
if [[ -z "${COMMAND}" ]]; then
  usage
  exit 2
fi
shift || true

case "${COMMAND}" in
  mark)
    echo $(( $(date +%s) * 1000 ))
    exit 0
    ;;
  verify)
    ;;
  *)
    usage
    exit 2
    ;;
esac

require_cmd swift

SINCE_MS=""
SCENARIO=""
TELEMETRY_LOG="${HOME}/Library/Application Support/Syntic/logs/e2e-telemetry.ndjson"
CORE_FEED_LOG="${HOME}/Library/Application Support/Syntic/logs/core-feed-projection.ndjson"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since-ms)
      SINCE_MS="${2:-}"
      shift 2
      ;;
    --scenario)
      SCENARIO="${2:-}"
      shift 2
      ;;
    --telemetry-log)
      TELEMETRY_LOG="${2:-}"
      shift 2
      ;;
    --core-feed-log)
      CORE_FEED_LOG="${2:-}"
      shift 2
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${SINCE_MS}" || -z "${SCENARIO}" ]]; then
  echo "error: --since-ms and --scenario are required" >&2
  usage
  exit 2
fi

if ! [[ "${SINCE_MS}" =~ ^[0-9]+$ ]]; then
  echo "error: --since-ms must be an integer epoch in milliseconds" >&2
  exit 2
fi

if [[ ! -f "${TELEMETRY_LOG}" ]]; then
  echo "error: telemetry log not found: ${TELEMETRY_LOG}" >&2
  exit 1
fi

if [[ ! -f "${CORE_FEED_LOG}" ]]; then
  echo "error: core feed log not found: ${CORE_FEED_LOG}" >&2
  exit 1
fi

swift - "${SCENARIO}" "${SINCE_MS}" "${TELEMETRY_LOG}" "${CORE_FEED_LOG}" <<'SWIFT'
import Foundation

struct TelemetryEvent: Decodable {
    let timestampMs: UInt64
    let source: String
    let category: String
    let action: String
    let status: String
    let context: [String: String]
    let valueMs: UInt32?
}

struct CoreFeedProjectionEvent: Decodable {
    let timestampMs: UInt64
    let feedKind: String
    let source: String
    let itemID: UInt64
    let payloadJSON: String
}

struct CoreEventEnvelope: Decodable {
    let code: String?
    let permission: String?
    let status: String?
}

enum SmokeCheckError: Error {
    case invalidArgs
    case unsupportedScenario(String)
    case noData(String)
}

func decodeNDJSON<T: Decodable>(path: String, as type: T.Type) -> [T] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        return []
    }

    let decoder = JSONDecoder()
    return content
        .split(separator: "\n")
        .compactMap { line in
            guard let data = line.data(using: .utf8) else {
                return nil
            }
            return try? decoder.decode(type, from: data)
        }
}

func fail(_ reasons: [String]) -> Never {
    for reason in reasons {
        fputs("fail|smoke_check|\(reason)\n", stderr)
    }
    exit(1)
}

func telemetryHas(
    _ events: [TelemetryEvent],
    category: String,
    action: String,
    status: String? = nil,
    contextKey: String? = nil,
    contextValue: String? = nil
) -> Bool {
    events.contains { event in
        guard event.category == category, event.action == action else {
            return false
        }
        if let status, event.status != status {
            return false
        }
        if let contextKey, let contextValue {
            return event.context[contextKey] == contextValue
        }
        return true
    }
}

func coreHasPermission(
    _ events: [CoreEventEnvelope],
    permission: String,
    status: String
) -> Bool {
    events.contains { $0.permission == permission && $0.status == status }
}

func coreHasError(_ events: [CoreEventEnvelope], code: String) -> Bool {
    events.contains { $0.code == code }
}

do {
    guard CommandLine.arguments.count == 5 else {
        throw SmokeCheckError.invalidArgs
    }

    let scenario = CommandLine.arguments[1]
    guard let sinceMs = UInt64(CommandLine.arguments[2]) else {
        throw SmokeCheckError.invalidArgs
    }
    let telemetryPath = CommandLine.arguments[3]
    let coreFeedPath = CommandLine.arguments[4]

    let telemetryEventsAll = decodeNDJSON(path: telemetryPath, as: TelemetryEvent.self)
    let telemetryEvents = telemetryEventsAll.filter { $0.timestampMs >= sinceMs }
    guard !telemetryEvents.isEmpty else {
        throw SmokeCheckError.noData("no telemetry events found since \(sinceMs)")
    }

    let feedEventsAll = decodeNDJSON(path: coreFeedPath, as: CoreFeedProjectionEvent.self)
    let coreEvents: [CoreEventEnvelope] = feedEventsAll
        .filter { $0.timestampMs >= sinceMs && $0.feedKind == "core_event" }
        .compactMap { event in
            guard let data = event.payloadJSON.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(CoreEventEnvelope.self, from: data)
        }

    var failures: [String] = []
    switch scenario {
    case "direct_injection":
        if !telemetryHas(telemetryEvents, category: "stt", action: "transcription_completed", status: "ok") {
            failures.append("missing stt transcription_completed status=ok")
        }
        if !telemetryHas(
            telemetryEvents,
            category: "injection",
            action: "result",
            status: "ok",
            contextKey: "disposition",
            contextValue: "injected"
        ) {
            failures.append("missing injection result disposition=injected status=ok")
        }
        if !telemetryHas(
            telemetryEvents,
            category: "e2e_phase",
            action: "transition",
            status: "ok",
            contextKey: "to_phase",
            contextValue: "reviewing"
        ) {
            failures.append("missing phase transition to reviewing")
        }
        if !telemetryHas(
            telemetryEvents,
            category: "e2e_phase",
            action: "transition",
            status: "ok",
            contextKey: "to_phase",
            contextValue: "idle"
        ) {
            failures.append("missing phase transition to idle")
        }

    case "clipboard_fallback":
        if !telemetryHas(telemetryEvents, category: "stt", action: "transcription_completed", status: "ok") {
            failures.append("missing stt transcription_completed status=ok")
        }
        if !telemetryHas(
            telemetryEvents,
            category: "injection",
            action: "result",
            status: "fallback",
            contextKey: "disposition",
            contextValue: "clipboard_fallback"
        ) {
            failures.append("missing injection result disposition=clipboard_fallback status=fallback")
        }

    case "stt_permission_denied":
        if !telemetryHas(
            telemetryEvents,
            category: "permission",
            action: "speech_recognition_request",
            status: "denied"
        ) {
            failures.append("missing permission telemetry speech_recognition_request denied")
        }
        if !telemetryHas(
            telemetryEvents,
            category: "stt",
            action: "transcription_failed",
            status: "failed",
            contextKey: "error_code",
            contextValue: "speech_permission_denied"
        ) {
            failures.append("missing stt transcription_failed with error_code=speech_permission_denied")
        }
        if !coreHasPermission(coreEvents, permission: "speech_recognition", status: "denied") {
            failures.append("missing core permission event speech_recognition denied")
        }
        if !coreHasError(coreEvents, code: "speech_permission_denied") {
            failures.append("missing core error event code=speech_permission_denied")
        }

    default:
        throw SmokeCheckError.unsupportedScenario(scenario)
    }

    if !failures.isEmpty {
        fail(failures)
    }

    print("ok|smoke_check|scenario=\(scenario)")
    print("ok|smoke_check|telemetry_events=\(telemetryEvents.count)")
    print("ok|smoke_check|core_events=\(coreEvents.count)")
} catch SmokeCheckError.invalidArgs {
    fputs("error: invalid arguments\n", stderr)
    exit(2)
} catch SmokeCheckError.unsupportedScenario(let scenario) {
    fputs("error: unsupported scenario '\(scenario)'\n", stderr)
    exit(2)
} catch SmokeCheckError.noData(let message) {
    fputs("error: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
SWIFT
