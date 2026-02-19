import Foundation

struct ToolExecutionPlan {
    let invocationID: String
    let transcript: String
    let origin: String
    let intentKind: String
    let intentSummary: String
    let confidencePercent: UInt8
    let safetyDecision: String
    let destructive: Bool
    let safetyReason: String
}

enum ToolExecutionOutcome: String {
    case executed
    case simulated
    case rejected
}

struct ToolExecutionResult {
    let outcome: ToolExecutionOutcome
    let detail: String
    let artifactPath: String?
}

protocol ToolExecuting {
    var executionLogPath: String { get }
    func execute(plan: ToolExecutionPlan) throws -> ToolExecutionResult
}

enum ToolExecutorError: Error {
    case ioFailure(String)
}

/// File-backed executor for technical E2E. It keeps effects local and auditable.
final class FileBackedToolExecutor: ToolExecuting {
    let executionLogPath: String

    private let fileManager: FileManager
    private let executionLogURL: URL
    private let notesURL: URL
    private let timersURL: URL

    init(fileManager: FileManager = .default, rootDirectoryURL: URL? = nil) {
        self.fileManager = fileManager

        let root: URL
        if let rootDirectoryURL {
            root = rootDirectoryURL
        } else {
            let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            root = appSupportURL.appendingPathComponent("Syntic", isDirectory: true)
        }
        executionLogURL = root.appendingPathComponent("tool-runtime-executions.ndjson", isDirectory: false)
        notesURL = root.appendingPathComponent("tool-runtime-notes.md", isDirectory: false)
        timersURL = root.appendingPathComponent("tool-runtime-timers.ndjson", isDirectory: false)
        executionLogPath = executionLogURL.path
    }

    func execute(plan: ToolExecutionPlan) throws -> ToolExecutionResult {
        try ensureDirectories()

        let result: ToolExecutionResult
        if plan.safetyDecision == "reject" {
            result = ToolExecutionResult(
                outcome: .rejected,
                detail: "Safety decision rejected the command (\(plan.safetyReason)).",
                artifactPath: nil
            )
        } else {
            switch plan.intentKind {
            case "save_note":
                try appendLine(
                    value: "- [\(Self.isoTimestamp())] \(plan.transcript)\n",
                    to: notesURL
                )
                result = ToolExecutionResult(
                    outcome: .executed,
                    detail: "Note persisted to local tool-runtime notes file.",
                    artifactPath: notesURL.path
                )
            case "set_timer":
                let timerRecord = TimerExecutionRecord(
                    invocationID: plan.invocationID,
                    createdAtMs: Self.nowMs(),
                    transcript: plan.transcript,
                    summary: plan.intentSummary
                )
                try appendNDJSON(value: timerRecord, to: timersURL)
                result = ToolExecutionResult(
                    outcome: .executed,
                    detail: "Timer execution record persisted.",
                    artifactPath: timersURL.path
                )
            case "move_file", "rename_file":
                result = ToolExecutionResult(
                    outcome: .simulated,
                    detail: "Destructive file operation is currently simulation-only.",
                    artifactPath: nil
                )
            default:
                result = ToolExecutionResult(
                    outcome: .rejected,
                    detail: "Unsupported or unknown intent kind (\(plan.intentKind)).",
                    artifactPath: nil
                )
            }
        }

        let logRecord = ExecutionLogRecord(
            invocationID: plan.invocationID,
            createdAtMs: Self.nowMs(),
            origin: plan.origin,
            intentKind: plan.intentKind,
            intentSummary: plan.intentSummary,
            confidencePercent: plan.confidencePercent,
            safetyDecision: plan.safetyDecision,
            destructive: plan.destructive,
            safetyReason: plan.safetyReason,
            outcome: result.outcome.rawValue,
            detail: result.detail,
            artifactPath: result.artifactPath
        )
        try appendNDJSON(value: logRecord, to: executionLogURL)
        return result
    }

    private func ensureDirectories() throws {
        let directoryURL = executionLogURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw ToolExecutorError.ioFailure("directory_create_failed: \(error.localizedDescription)")
        }
    }

    private func appendNDJSON<T: Encodable>(value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw ToolExecutorError.ioFailure("encode_failed: \(error.localizedDescription)")
        }

        guard let line = String(data: data, encoding: .utf8) else {
            throw ToolExecutorError.ioFailure("utf8_conversion_failed")
        }
        try appendLine(value: "\(line)\n", to: url)
    }

    private func appendLine(value: String, to url: URL) throws {
        guard let data = value.data(using: .utf8) else {
            throw ToolExecutorError.ioFailure("line_utf8_conversion_failed")
        }

        if !fileManager.fileExists(atPath: url.path) {
            do {
                try data.write(to: url, options: .atomic)
                return
            } catch {
                throw ToolExecutorError.ioFailure("initial_write_failed: \(error.localizedDescription)")
            }
        }

        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            throw ToolExecutorError.ioFailure("append_failed: \(error.localizedDescription)")
        }
    }

    private static func nowMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }

    private static func isoTimestamp() -> String {
        isoFormatter.string(from: Date())
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct ExecutionLogRecord: Codable {
    let invocationID: String
    let createdAtMs: UInt64
    let origin: String
    let intentKind: String
    let intentSummary: String
    let confidencePercent: UInt8
    let safetyDecision: String
    let destructive: Bool
    let safetyReason: String
    let outcome: String
    let detail: String
    let artifactPath: String?
}

private struct TimerExecutionRecord: Codable {
    let invocationID: String
    let createdAtMs: UInt64
    let transcript: String
    let summary: String
}
