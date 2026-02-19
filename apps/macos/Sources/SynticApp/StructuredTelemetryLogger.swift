import Foundation

struct StructuredTelemetryEvent: Encodable {
    let timestampMs: UInt64
    let source: String
    let category: String
    let action: String
    let status: String
    let context: [String: String]
    let valueMs: UInt32?

    init(
        source: String,
        category: String,
        action: String,
        status: String,
        context: [String: String],
        valueMs: UInt32? = nil
    ) {
        timestampMs = UInt64(Date().timeIntervalSince1970 * 1_000)
        self.source = source
        self.category = category
        self.action = action
        self.status = status
        self.context = context
        self.valueMs = valueMs
    }
}

protocol StructuredTelemetryLogging {
    var logFilePath: String { get }
    func append(_ event: StructuredTelemetryEvent)
}

final class NDJSONTelemetryLogger: StructuredTelemetryLogging {
    let logFilePath: String

    private let fileURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.syntic.telemetry-log", qos: .utility)

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = appSupportURL
            .appendingPathComponent("Syntic", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("e2e-telemetry.ndjson", isDirectory: false)
        logFilePath = fileURL.path
    }

    func append(_ event: StructuredTelemetryEvent) {
        queue.async { [fileManager, fileURL] in
            do {
                let directoryURL = fileURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                var payloadData = try encoder.encode(event)
                payloadData.append(0x0A)

                if !fileManager.fileExists(atPath: fileURL.path) {
                    try payloadData.write(to: fileURL, options: .atomic)
                    return
                }

                let fileHandle = try FileHandle(forWritingTo: fileURL)
                defer {
                    try? fileHandle.close()
                }
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: payloadData)
            } catch {
                // Telemetry write failures must never break flow execution.
            }
        }
    }
}
