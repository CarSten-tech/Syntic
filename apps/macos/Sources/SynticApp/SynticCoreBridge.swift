import Foundation
import SynticFFI

protocol SynticCoreVersionProviding {
    var isFFILinked: Bool { get }
    func coreVersion() -> String
    func healthSnapshotJSON() -> String
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
        guard let payloadPointer = syntic_runtime_health_json() else {
            return "{\"service_name\":\"syntic-core\",\"status\":\"ffi-null-payload\"}"
        }

        defer {
            syntic_string_free(payloadPointer)
        }

        return String(cString: payloadPointer)
    }
}
