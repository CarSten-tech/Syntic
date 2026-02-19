import Foundation
import SynticFFI

protocol SynticCoreVersionProviding {
    var isFFILinked: Bool { get }
    func coreVersion() -> String
    func healthSnapshotJSON() -> String
    func dictationStateJSON() -> String
    func dictationReset() -> UInt8
    func dictationStart() -> UInt8
    func dictationAppendPartial(_ text: String) -> UInt8
    func dictationFinalizeReview(_ text: String) -> UInt8
    func dictationConfirm() -> UInt8
    func dictationCancel() -> UInt8
    func dictationFail(_ message: String) -> UInt8
    func commandClassifyJSON(_ utterance: String) -> String
    func commandSafetyJSON(_ utterance: String) -> String
    func coreEventsSinceJSON(lastSeenEventID: UInt64, limit: UInt16) -> String
    func coreEventsClear() -> UInt8
    func domainEventsSinceJSON(lastSeenEventID: UInt64, limit: UInt16) -> String
    func toolRuntimeSignalsSinceJSON(lastSeenSignalID: UInt64, limit: UInt16) -> String
    func domainEventsClear() -> UInt8
    func reportCoreErrorEvent(source: String, code: String, message: String) -> UInt8
    func reportCorePermissionEvent(
        source: String,
        permission: String,
        status: String,
        detail: String
    ) -> UInt8
    func reportCoreTelemetryEvent(
        source: String,
        category: String,
        action: String,
        status: String,
        contextJSON: String,
        valueMs: UInt32
    ) -> UInt8
    func reportCoreSessionHistoryRecord(
        outcome: String,
        transcript: String,
        locale: String,
        routeProvider: String,
        durationMs: UInt32?,
        errorCode: String?,
        injectionDisposition: String?
    ) -> UInt8
    func markCoreSessionHistoryLastConfirmedUndone() -> UInt8
    func coreSessionHistorySinceJSON(lastSeenRecordID: UInt64, limit: UInt16) -> String
    func coreSessionHistoryClear() -> UInt8
    func sttRouteJSON(
        preferenceMode: UInt8,
        sensitiveModeEnabled: Bool,
        networkAvailable: Bool,
        utteranceDurationMs: UInt32
    ) -> String
}

/// Swift-side FFI adapter for the Rust `syntic-ffi` static library.
struct SynticCoreBridge: SynticCoreVersionProviding {
    var isFFILinked: Bool {
        true
    }

    func coreVersion() -> String {
        guard let versionPointer = syntic_core_version() else {
            return "ffi-version-unavailable"
        }

        return String(cString: versionPointer)
    }

    func healthSnapshotJSON() -> String {
        readHeapJsonPayload(fallback: "{\"service_name\":\"syntic-core\",\"status\":\"ffi-null-payload\"}") {
            syntic_runtime_health_json()
        }
    }

    func dictationStateJSON() -> String {
        readHeapJsonPayload(fallback: "{\"phase\":\"ffi-null-payload\"}") {
            syntic_dictation_state_json()
        }
    }

    func dictationReset() -> UInt8 {
        syntic_dictation_reset()
    }

    func dictationStart() -> UInt8 {
        syntic_dictation_start()
    }

    func dictationAppendPartial(_ text: String) -> UInt8 {
        text.withCString { utf8Pointer in
            syntic_dictation_append_partial(utf8Pointer)
        }
    }

    func dictationFinalizeReview(_ text: String) -> UInt8 {
        text.withCString { utf8Pointer in
            syntic_dictation_finalize_review(utf8Pointer)
        }
    }

    func dictationConfirm() -> UInt8 {
        syntic_dictation_confirm()
    }

    func dictationCancel() -> UInt8 {
        syntic_dictation_cancel()
    }

    func dictationFail(_ message: String) -> UInt8 {
        message.withCString { utf8Pointer in
            syntic_dictation_fail(utf8Pointer)
        }
    }

    func commandClassifyJSON(_ utterance: String) -> String {
        utterance.withCString { utf8Pointer in
            readHeapJsonPayload(fallback: "{\"kind\":\"ffi-null-payload\"}") {
                syntic_command_classify_json(utf8Pointer)
            }
        }
    }

    func commandSafetyJSON(_ utterance: String) -> String {
        utterance.withCString { utf8Pointer in
            readHeapJsonPayload(fallback: "{\"decision\":\"ffi-null-payload\"}") {
                syntic_command_safety_json(utf8Pointer)
            }
        }
    }

    func coreEventsSinceJSON(lastSeenEventID: UInt64, limit: UInt16) -> String {
        readHeapJsonPayload(fallback: "{\"events\":[]}") {
            syntic_core_events_since_json(lastSeenEventID, limit)
        }
    }

    func coreEventsClear() -> UInt8 {
        syntic_core_events_clear()
    }

    func domainEventsSinceJSON(lastSeenEventID: UInt64, limit: UInt16) -> String {
        readHeapJsonPayload(fallback: "{\"events\":[]}") {
            syntic_domain_events_since_json(lastSeenEventID, limit)
        }
    }

    func toolRuntimeSignalsSinceJSON(lastSeenSignalID: UInt64, limit: UInt16) -> String {
        readHeapJsonPayload(fallback: "{\"signals\":[]}") {
            syntic_tool_runtime_signals_since_json(lastSeenSignalID, limit)
        }
    }

    func domainEventsClear() -> UInt8 {
        syntic_domain_events_clear()
    }

    func reportCoreErrorEvent(source: String, code: String, message: String) -> UInt8 {
        source.withCString { sourcePointer in
            code.withCString { codePointer in
                message.withCString { messagePointer in
                    syntic_core_event_report_error(sourcePointer, codePointer, messagePointer)
                }
            }
        }
    }

    func reportCorePermissionEvent(
        source: String,
        permission: String,
        status: String,
        detail: String
    ) -> UInt8 {
        source.withCString { sourcePointer in
            permission.withCString { permissionPointer in
                status.withCString { statusPointer in
                    detail.withCString { detailPointer in
                        syntic_core_event_report_permission(
                            sourcePointer,
                            permissionPointer,
                            statusPointer,
                            detailPointer
                        )
                    }
                }
            }
        }
    }

    func reportCoreTelemetryEvent(
        source: String,
        category: String,
        action: String,
        status: String,
        contextJSON: String,
        valueMs: UInt32
    ) -> UInt8 {
        source.withCString { sourcePointer in
            category.withCString { categoryPointer in
                action.withCString { actionPointer in
                    status.withCString { statusPointer in
                        contextJSON.withCString { contextPointer in
                            syntic_core_event_report_telemetry(
                                sourcePointer,
                                categoryPointer,
                                actionPointer,
                                statusPointer,
                                contextPointer,
                                valueMs
                            )
                        }
                    }
                }
            }
        }
    }

    func reportCoreSessionHistoryRecord(
        outcome: String,
        transcript: String,
        locale: String,
        routeProvider: String,
        durationMs: UInt32?,
        errorCode: String?,
        injectionDisposition: String?
    ) -> UInt8 {
        outcome.withCString { outcomePointer in
            transcript.withCString { transcriptPointer in
                locale.withCString { localePointer in
                    routeProvider.withCString { routeProviderPointer in
                        withOptionalCString(errorCode) { errorCodePointer in
                            withOptionalCString(injectionDisposition) { injectionDispositionPointer in
                                syntic_session_history_record(
                                    outcomePointer,
                                    transcriptPointer,
                                    localePointer,
                                    routeProviderPointer,
                                    durationMs ?? 0,
                                    errorCodePointer,
                                    injectionDispositionPointer
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func markCoreSessionHistoryLastConfirmedUndone() -> UInt8 {
        syntic_session_history_mark_last_confirmed_undone()
    }

    func coreSessionHistorySinceJSON(lastSeenRecordID: UInt64, limit: UInt16) -> String {
        readHeapJsonPayload(fallback: "{\"records\":[]}") {
            syntic_session_history_since_json(lastSeenRecordID, limit)
        }
    }

    func coreSessionHistoryClear() -> UInt8 {
        syntic_session_history_clear()
    }

    func sttRouteJSON(
        preferenceMode: UInt8,
        sensitiveModeEnabled: Bool,
        networkAvailable: Bool,
        utteranceDurationMs: UInt32
    ) -> String {
        readHeapJsonPayload(fallback: "{\"provider\":\"ffi-null-payload\"}") {
            syntic_stt_route_json(
                preferenceMode,
                sensitiveModeEnabled ? 1 : 0,
                networkAvailable ? 1 : 0,
                utteranceDurationMs
            )
        }
    }
}

private extension SynticCoreBridge {
    func readHeapJsonPayload(
        fallback: String,
        producer: () -> UnsafeMutablePointer<CChar>?
    ) -> String {
        guard let payloadPointer = producer() else {
            return fallback
        }

        defer {
            syntic_string_free(payloadPointer)
        }

        return String(cString: payloadPointer)
    }

    func withOptionalCString<T>(_ value: String?, _ body: (UnsafePointer<CChar>?) -> T) -> T {
        guard let value, !value.isEmpty else {
            return body(nil)
        }
        return value.withCString { pointer in
            body(pointer)
        }
    }
}
