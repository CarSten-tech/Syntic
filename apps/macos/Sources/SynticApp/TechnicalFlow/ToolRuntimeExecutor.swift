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
    let moveDestinationHint: String?
    let renameTargetHint: String?
    let timerDurationHint: String?
}

enum ToolExecutionOutcome: String {
    case executed
    case simulated
    case rejected
}

enum DestructiveExecutionMode: String {
    case dryRunOnly = "dry_run_only"
    case allowExecution = "allow_execution"

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        environment["SYNTIC_ALLOW_DESTRUCTIVE_EXECUTION"] == "1" ? .allowExecution : .dryRunOnly
    }
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
    private let finderContextProvider: FinderContextProviding
    private let destructiveExecutionMode: DestructiveExecutionMode

    private let executionLogURL: URL
    private let notesURL: URL
    private let timersURL: URL

    init(
        fileManager: FileManager = .default,
        rootDirectoryURL: URL? = nil,
        finderContextProvider: FinderContextProviding = MacOSFinderContextAdapter(),
        destructiveExecutionMode: DestructiveExecutionMode = .fromEnvironment()
    ) {
        self.fileManager = fileManager
        self.finderContextProvider = finderContextProvider
        self.destructiveExecutionMode = destructiveExecutionMode

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
            case "move_file":
                result = try executeMoveFile(plan: plan)
            case "rename_file":
                result = try executeRenameFile(plan: plan)
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
            destructiveExecutionMode: destructiveExecutionMode.rawValue,
            outcome: result.outcome.rawValue,
            detail: result.detail,
            artifactPath: result.artifactPath
        )
        try appendNDJSON(value: logRecord, to: executionLogURL)
        return result
    }

    private func executeMoveFile(plan: ToolExecutionPlan) throws -> ToolExecutionResult {
        let destinationHint = sanitizeToken(plan.moveDestinationHint ?? "")
        let transcriptHint = parsedDestinationTokenFromTranscript(plan.transcript) ?? ""
        let destinationToken = destinationHint.isEmpty ? transcriptHint : destinationHint

        guard let destinationURL = destinationDirectoryURL(from: destinationToken) else {
            return ToolExecutionResult(
                outcome: .rejected,
                detail: "Move rejected: destination path missing or unsupported.",
                artifactPath: nil
            )
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ToolExecutionResult(
                outcome: .rejected,
                detail: "Move rejected: destination directory does not exist (\(destinationURL.path)).",
                artifactPath: destinationURL.path
            )
        }

        let selection = resolveFinderSelection()
        guard case let .success(selectedURLs) = selection else {
            if case let .rejected(result) = selection {
                return result
            }
            return ToolExecutionResult(
                outcome: .rejected,
                detail: "Finder selection unavailable.",
                artifactPath: nil
            )
        }

        let preview = selectedURLs
            .map { "\($0.lastPathComponent) -> \(destinationURL.path)" }
            .joined(separator: ", ")
        if destructiveExecutionMode == .dryRunOnly {
            return ToolExecutionResult(
                outcome: .simulated,
                detail: "Move simulated only. Set SYNTIC_ALLOW_DESTRUCTIVE_EXECUTION=1 to execute. \(preview)",
                artifactPath: destinationURL.path
            )
        }

        for sourceURL in selectedURLs {
            let targetURL = destinationURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
            try fileManager.moveItem(at: sourceURL, to: targetURL)
        }

        return ToolExecutionResult(
            outcome: .executed,
            detail: "Moved \(selectedURLs.count) item(s) to \(destinationURL.path).",
            artifactPath: destinationURL.path
        )
    }

    private func executeRenameFile(plan: ToolExecutionPlan) throws -> ToolExecutionResult {
        let renameHint = sanitizeToken(plan.renameTargetHint ?? "")
        let transcriptHint = parsedRenameTargetFromTranscript(plan.transcript) ?? ""
        let newName = renameHint.isEmpty ? transcriptHint : renameHint

        guard !newName.isEmpty else {
            return ToolExecutionResult(
                outcome: .rejected,
                detail: "Rename rejected: target name missing or invalid.",
                artifactPath: nil
            )
        }

        if newName.contains("/") || newName.contains(":") {
            return ToolExecutionResult(
                outcome: .rejected,
                detail: "Rename rejected: target name contains invalid path characters.",
                artifactPath: nil
            )
        }

        let selection = resolveFinderSelection()
        guard case let .success(selectedURLs) = selection else {
            if case let .rejected(result) = selection {
                return result
            }
            return ToolExecutionResult(
                outcome: .rejected,
                detail: "Finder selection unavailable.",
                artifactPath: nil
            )
        }

        guard selectedURLs.count == 1 else {
            return ToolExecutionResult(
                outcome: .rejected,
                detail: "Rename rejected: exactly one selected item required, got \(selectedURLs.count).",
                artifactPath: nil
            )
        }

        let sourceURL = selectedURLs[0]
        let targetURL = sourceURL.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: false)

        if sourceURL.lastPathComponent == newName {
            return ToolExecutionResult(
                outcome: .simulated,
                detail: "Rename skipped: selected item already has target name.",
                artifactPath: sourceURL.path
            )
        }

        if destructiveExecutionMode == .dryRunOnly {
            return ToolExecutionResult(
                outcome: .simulated,
                detail: "Rename simulated only. Set SYNTIC_ALLOW_DESTRUCTIVE_EXECUTION=1 to execute. \(sourceURL.lastPathComponent) -> \(newName)",
                artifactPath: sourceURL.path
            )
        }

        try fileManager.moveItem(at: sourceURL, to: targetURL)
        return ToolExecutionResult(
            outcome: .executed,
            detail: "Renamed \(sourceURL.lastPathComponent) to \(newName).",
            artifactPath: targetURL.path
        )
    }

    private func resolveFinderSelection() -> FinderSelectionResolution {
        let snapshot = finderContextProvider.currentSelectionSnapshot()
        guard snapshot.status == .ok else {
            let detail = snapshot.errorMessage
                ?? "Finder selection unavailable (\(snapshot.status.rawValue))."
            return .rejected(
                ToolExecutionResult(
                    outcome: .rejected,
                    detail: detail,
                    artifactPath: nil
                )
            )
        }

        let selectedURLs = snapshot.selectedPaths
            .map { URL(fileURLWithPath: $0) }
            .filter { !$0.path.isEmpty }

        guard !selectedURLs.isEmpty else {
            return .rejected(
                ToolExecutionResult(
                    outcome: .rejected,
                    detail: "Finder selection is empty.",
                    artifactPath: nil
                )
            )
        }
        return .success(selectedURLs)
    }

    private func parsedDestinationTokenFromTranscript(_ transcript: String) -> String? {
        guard let tail = capturedTail(afterAnyOf: [" to ", " nach "], in: transcript) else {
            return nil
        }

        let destinationToken = sanitizeToken(tail)
        return destinationToken.isEmpty ? nil : destinationToken
    }

    private func destinationDirectoryURL(from destinationToken: String) -> URL? {
        guard !destinationToken.isEmpty else {
            return nil
        }
        switch destinationToken.lowercased() {
        case "desktop":
            return fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
        case "documents", "dokumente":
            return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        case "downloads":
            return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        default:
            let expanded = (destinationToken as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else {
                return nil
            }
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
    }

    private func parsedRenameTargetFromTranscript(_ transcript: String) -> String? {
        guard let tail = capturedTail(afterAnyOf: [" to ", " zu ", " als "], in: transcript) else {
            return nil
        }

        let candidate = sanitizeToken(tail)
        return candidate.isEmpty ? nil : candidate
    }

    private func capturedTail(afterAnyOf markers: [String], in text: String) -> String? {
        for marker in markers {
            if let range = text.range(of: marker, options: [.caseInsensitive]) {
                return String(text[range.upperBound...])
            }
        }
        return nil
    }

    private func sanitizeToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\""), let closingIndex = trimmed.dropFirst().firstIndex(of: "\"") {
            let quoted = trimmed[trimmed.index(after: trimmed.startIndex) ..< closingIndex]
            return String(quoted).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("'"), let closingIndex = trimmed.dropFirst().firstIndex(of: "'") {
            let quoted = trimmed[trimmed.index(after: trimmed.startIndex) ..< closingIndex]
            return String(quoted).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
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

private enum FinderSelectionResolution {
    case success([URL])
    case rejected(ToolExecutionResult)
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
    let destructiveExecutionMode: String
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
