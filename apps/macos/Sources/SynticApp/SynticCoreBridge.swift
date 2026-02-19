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
}
