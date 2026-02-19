import Foundation

struct CoreFeedProjectionEvent: Encodable {
    let timestampMs: UInt64
    let feedKind: String
    let source: String
    let itemID: UInt64
    let payloadJSON: String

    init(feedKind: String, source: String, itemID: UInt64, payloadJSON: String) {
        timestampMs = UInt64(Date().timeIntervalSince1970 * 1_000)
        self.feedKind = feedKind
        self.source = source
        self.itemID = itemID
        self.payloadJSON = payloadJSON
    }
}

protocol CoreFeedProjecting {
    var logFilePath: String { get }
    func append(_ event: CoreFeedProjectionEvent)
}

final class NDJSONCoreFeedProjector: CoreFeedProjecting {
    let logFilePath: String

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.syntic.core-feed-projection", qos: .utility)
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let logsDirectory = appSupportURL
            .appendingPathComponent("Syntic", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        fileURL = logsDirectory.appendingPathComponent("core-feed-projection.ndjson", isDirectory: false)
        logFilePath = fileURL.path
    }

    func append(_ event: CoreFeedProjectionEvent) {
        queue.async { [fileManager, fileURL] in
            do {
                let directoryURL = fileURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let encoded = try encoder.encode(event)
                guard let line = String(data: encoded, encoding: .utf8)?.appending("\n"),
                      let data = line.data(using: .utf8)
                else {
                    return
                }

                if !fileManager.fileExists(atPath: fileURL.path) {
                    try data.write(to: fileURL, options: .atomic)
                    return
                }

                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Feed projection must never break runtime flow.
            }
        }
    }
}
