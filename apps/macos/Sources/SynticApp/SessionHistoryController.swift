import Foundation

enum SessionOutcome: String, Codable {
    case confirmed
    case cancelled
    case failed
}

enum SessionInjectionDisposition: String, Codable {
    case injected
    case clipboardFallback = "clipboard_fallback"
    case failed
    case unknown
}

struct SessionHistoryRecord: Codable, Identifiable, Equatable {
    let id: String
    let createdAtMs: UInt64
    let durationMs: UInt32?
    let locale: String
    let routeProvider: String
    let outcome: SessionOutcome
    let transcript: String
    let errorCode: String?
    let injectionDisposition: SessionInjectionDisposition?
    var undoneAtMs: UInt64?
}

struct SessionHistorySnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var records: [SessionHistoryRecord]

    func normalized(maxRecords: Int) -> SessionHistorySnapshot {
        var normalized = self
        normalized.schemaVersion = Self.currentSchemaVersion
        if normalized.records.count > maxRecords {
            normalized.records = Array(normalized.records.suffix(maxRecords))
        }
        return normalized
    }
}

struct SessionHistoryLoadResult {
    let snapshot: SessionHistorySnapshot
    let warningMessage: String?
}

protocol SessionHistoryPersisting {
    var historyFileURL: URL { get }
    func load(maxRecords: Int) throws -> SessionHistoryLoadResult
    func save(snapshot: SessionHistorySnapshot) throws
}

struct FileSessionHistoryStore: SessionHistoryPersisting {
    private let fileManager: FileManager
    let historyFileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        historyFileURL = appSupportURL
            .appendingPathComponent("Syntic", isDirectory: true)
            .appendingPathComponent("session-history.json", isDirectory: false)
    }

    func load(maxRecords: Int) throws -> SessionHistoryLoadResult {
        try ensureParentDirectory()

        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            let empty = SessionHistorySnapshot(schemaVersion: SessionHistorySnapshot.currentSchemaVersion, records: [])
            try save(snapshot: empty)
            return SessionHistoryLoadResult(snapshot: empty, warningMessage: nil)
        }

        let data = try Data(contentsOf: historyFileURL)
        let decoder = JSONDecoder()

        do {
            let decoded = try decoder.decode(SessionHistorySnapshot.self, from: data).normalized(maxRecords: maxRecords)
            try save(snapshot: decoded)
            return SessionHistoryLoadResult(snapshot: decoded, warningMessage: nil)
        } catch is DecodingError {
            let warning = try recoverFromCorruptHistory()
            let empty = SessionHistorySnapshot(schemaVersion: SessionHistorySnapshot.currentSchemaVersion, records: [])
            return SessionHistoryLoadResult(snapshot: empty, warningMessage: warning)
        }
    }

    func save(snapshot: SessionHistorySnapshot) throws {
        try ensureParentDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: historyFileURL, options: .atomic)
    }

    private func ensureParentDirectory() throws {
        let directoryURL = historyFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func recoverFromCorruptHistory() throws -> String {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let backupURL = historyFileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(timestamp).json")

        try? fileManager.removeItem(at: backupURL)
        try fileManager.moveItem(at: historyFileURL, to: backupURL)

        let empty = SessionHistorySnapshot(schemaVersion: SessionHistorySnapshot.currentSchemaVersion, records: [])
        try save(snapshot: empty)
        return "Ungültige Session-History erkannt. Backup erstellt: \(backupURL.path)"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

@MainActor
final class SessionHistoryController: ObservableObject {
    @Published private(set) var records: [SessionHistoryRecord] = []
    @Published private(set) var lastPersistError: String?
    @Published private(set) var lastLoadWarning: String?
    @Published private(set) var lastSavedAt: Date?

    let historyFilePath: String
    let maxRecords: Int

    private let store: SessionHistoryPersisting

    init(store: SessionHistoryPersisting = FileSessionHistoryStore(), maxRecords: Int = 200) {
        self.store = store
        self.maxRecords = max(maxRecords, 1)
        historyFilePath = store.historyFileURL.path
        reloadFromDisk()
    }

    var persistenceSummary: String {
        if let error = lastPersistError {
            return "save-error: \(error)"
        }
        if let warning = lastLoadWarning {
            return "warning: \(warning)"
        }
        if let savedAt = lastSavedAt {
            return "saved: \(Self.savedAtFormatter.string(from: savedAt))"
        }
        return "not-saved-yet"
    }

    var latestRecordSummary: String {
        guard let latest = records.last else {
            return "none"
        }
        let durationValue = latest.durationMs.map { "\($0)ms" } ?? "-"
        return "outcome=\(latest.outcome.rawValue), provider=\(latest.routeProvider), duration=\(durationValue), locale=\(latest.locale)"
    }

    var hasUndoCandidate: Bool {
        records.last(where: { $0.outcome == .confirmed && $0.undoneAtMs == nil }) != nil
    }

    func record(
        outcome: SessionOutcome,
        transcript: String,
        locale: String,
        routeProvider: String,
        durationMs: UInt32?,
        errorCode: String?,
        injectionDisposition: SessionInjectionDisposition?
    ) {
        let record = SessionHistoryRecord(
            id: UUID().uuidString,
            createdAtMs: Self.nowMs(),
            durationMs: durationMs,
            locale: locale,
            routeProvider: routeProvider,
            outcome: outcome,
            transcript: transcript,
            errorCode: errorCode,
            injectionDisposition: injectionDisposition,
            undoneAtMs: nil
        )
        records.append(record)
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
        persist()
    }

    func markLastConfirmedAsUndone() -> SessionHistoryRecord? {
        guard let index = records.lastIndex(where: { $0.outcome == .confirmed && $0.undoneAtMs == nil }) else {
            return nil
        }
        records[index].undoneAtMs = Self.nowMs()
        let updated = records[index]
        persist()
        return updated
    }

    func clearHistory() {
        records.removeAll()
        persist()
    }

    func reloadFromDisk() {
        do {
            let result = try store.load(maxRecords: maxRecords)
            records = result.snapshot.records
            lastPersistError = nil
            lastLoadWarning = result.warningMessage
            lastSavedAt = Date()
        } catch {
            lastPersistError = "Load failed: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            let snapshot = SessionHistorySnapshot(
                schemaVersion: SessionHistorySnapshot.currentSchemaVersion,
                records: records
            ).normalized(maxRecords: maxRecords)
            records = snapshot.records
            try store.save(snapshot: snapshot)
            lastPersistError = nil
            lastSavedAt = Date()
        } catch {
            lastPersistError = "Save failed: \(error.localizedDescription)"
        }
    }

    private static func nowMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }

    private static let savedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
