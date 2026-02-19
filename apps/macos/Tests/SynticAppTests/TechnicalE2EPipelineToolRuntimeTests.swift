import Foundation
import XCTest
@testable import SynticApp

@MainActor
final class TechnicalE2EPipelineToolRuntimeTests: XCTestCase {
    func testReviewCancelAbortsPendingToolInvocationBeforeExecution() async throws {
        let fixture = makeFixture(transcript: "save note buy milk")
        defer { fixture.cleanup() }

        let reachedReviewOnCancel = await drivePipelineToReviewingState(fixture.pipeline)
        XCTAssertTrue(reachedReviewOnCancel)

        let beforeCancel = try decodeQueueSnapshot(from: fixture.pipeline.toolRuntimeQueueJSON)
        XCTAssertEqual(beforeCancel.pending.count, 1)

        fixture.pipeline.cancelReview()

        let afterCancel = try decodeQueueSnapshot(from: fixture.pipeline.toolRuntimeQueueJSON)
        XCTAssertEqual(afterCancel.pending.count, 0)
        XCTAssertEqual(afterCancel.running.count, 0)
        XCTAssertEqual(afterCancel.cancelled.count, 1)
        XCTAssertEqual(afterCancel.completed.count, 0)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.toolExecutor.executionLogPath))
    }

    func testReviewConfirmCommitsPendingInvocationAndWritesExecutionLog() async throws {
        let fixture = makeFixture(transcript: "save note architecture review")
        defer { fixture.cleanup() }

        let reachedReviewOnConfirm = await drivePipelineToReviewingState(fixture.pipeline)
        XCTAssertTrue(reachedReviewOnConfirm)

        fixture.pipeline.confirmReview()

        let completedInvocation = await waitUntil(timeoutMs: 5_000) {
            (try? self.decodeQueueSnapshot(from: fixture.pipeline.toolRuntimeQueueJSON).completed.count) == 1
        }
        XCTAssertTrue(completedInvocation)

        let queue = try decodeQueueSnapshot(from: fixture.pipeline.toolRuntimeQueueJSON)
        XCTAssertEqual(queue.pending.count, 0)
        XCTAssertEqual(queue.running.count, 0)
        XCTAssertEqual(queue.completed.count, 1)
        XCTAssertEqual(queue.cancelled.count, 0)
        XCTAssertEqual(queue.failed.count, 0)

        let logURL = URL(fileURLWithPath: fixture.toolExecutor.executionLogPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))
        let logContents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(logContents.contains("\"outcome\":\"executed\""))
        XCTAssertTrue(logContents.contains("\"intentKind\":\"save_note\""))
    }

    private func makeFixture(transcript: String) -> PipelineFixture {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("syntic-tests-\(UUID().uuidString)", isDirectory: true)
        let toolExecutor = FileBackedToolExecutor(rootDirectoryURL: rootURL)

        let coreBridge = FakeCoreBridge()
        let settingsController = AppSettingsController(store: InMemoryAppSettingsStore(rootURL: rootURL))
        let sessionHistoryController = SessionHistoryController(store: InMemorySessionHistoryStore(rootURL: rootURL))

        let pipeline = TechnicalE2EPipeline(
            coreBridge: coreBridge,
            settingsController: settingsController,
            sessionHistoryController: sessionHistoryController,
            audioAdapter: FakeAudioCaptureAdapter(),
            hotkeyAdapter: NoopHotkeyAdapter(),
            localSttAdapter: ImmediateSuccessSTTAdapter(transcript: transcript),
            cloudSttAdapter: ImmediateSuccessSTTAdapter(transcript: transcript, providerIdentifier: "openai_whisper"),
            textInjectionAdapter: SuccessfulTextInjectionAdapter(),
            toolExecutor: toolExecutor,
            telemetryLogger: InMemoryTelemetryLogger()
        )

        return PipelineFixture(
            pipeline: pipeline,
            toolExecutor: toolExecutor,
            rootURL: rootURL
        )
    }

    private func waitUntil(timeoutMs: UInt64, condition: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    private func drivePipelineToReviewingState(_ pipeline: TechnicalE2EPipeline) async -> Bool {
        pipeline.triggerHotkeyAction()

        let reachedListening = await waitUntil(timeoutMs: 2_500) { pipeline.phase == "listening" }
        guard reachedListening else {
            return false
        }

        pipeline.triggerHotkeyAction()
        return await waitUntil(timeoutMs: 4_000) { pipeline.phase == "reviewing" }
    }

    private func decodeQueueSnapshot(from payload: String) throws -> QueueSnapshot {
        let data = try XCTUnwrap(payload.data(using: .utf8))
        return try JSONDecoder().decode(QueueSnapshot.self, from: data)
    }
}

private struct PipelineFixture {
    let pipeline: TechnicalE2EPipeline
    let toolExecutor: FileBackedToolExecutor
    let rootURL: URL

    func cleanup() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return
        }
        try? fileManager.removeItem(at: rootURL)
    }
}

private struct QueueSnapshot: Decodable {
    let pending: [PendingInvocation]
    let running: [String]
    let completed: [String]
    let cancelled: [String]
    let failed: [String]
}

private struct PendingInvocation: Decodable {
    let id: String
    let origin: String
    let transcript_length: Int
    let queued_at_ms: UInt64
    let intent_kind: String
    let safety_decision: String
    let destructive: Bool
}

private final class InMemoryAppSettingsStore: AppSettingsPersisting {
    let settingsFileURL: URL
    private var snapshot: AppSettingsSnapshot

    init(rootURL: URL) {
        settingsFileURL = rootURL.appendingPathComponent("settings.json", isDirectory: false)
        snapshot = .defaults
    }

    func load() throws -> AppSettingsLoadResult {
        AppSettingsLoadResult(snapshot: snapshot, warningMessage: nil)
    }

    func save(_ snapshot: AppSettingsSnapshot) throws {
        self.snapshot = snapshot.normalized()
    }
}

private final class InMemorySessionHistoryStore: SessionHistoryPersisting {
    let historyFileURL: URL
    private var snapshot: SessionHistorySnapshot

    init(rootURL: URL) {
        historyFileURL = rootURL.appendingPathComponent("session-history.json", isDirectory: false)
        snapshot = SessionHistorySnapshot(
            schemaVersion: SessionHistorySnapshot.currentSchemaVersion,
            records: []
        )
    }

    func load(maxRecords: Int) throws -> SessionHistoryLoadResult {
        SessionHistoryLoadResult(
            snapshot: snapshot.normalized(maxRecords: maxRecords),
            warningMessage: nil
        )
    }

    func save(snapshot: SessionHistorySnapshot) throws {
        self.snapshot = snapshot
    }
}

private final class FakeCoreBridge: SynticCoreVersionProviding {
    private var phase = "idle"
    private var liveTranscript = ""
    private var reviewTranscript = ""
    private var lastError: String?

    private var nextDomainEventID: UInt64 = 1
    private var nextToolSignalID: UInt64 = 1
    private var domainEvents: [DomainEventRecord] = []
    private var toolSignals: [ToolRuntimeSignalRecord] = []

    var isFFILinked: Bool {
        true
    }

    func coreVersion() -> String {
        "test-core"
    }

    func healthSnapshotJSON() -> String {
        "{\"service_name\":\"syntic-core\",\"version\":\"test-core\",\"status\":\"ready\"}"
    }

    func dictationStateJSON() -> String {
        let lastErrorJSON = lastError.map { "\"\($0)\"" } ?? "null"
        return """
        {"phase":"\(phase)","live_transcript":"\(liveTranscript)","review_transcript":"\(reviewTranscript)","last_error":\(lastErrorJSON),"requires_confirmation":\(phase == "reviewing")}
        """
    }

    func dictationReset() -> UInt8 {
        phase = "idle"
        liveTranscript = ""
        reviewTranscript = ""
        lastError = nil
        return 0
    }

    func dictationStart() -> UInt8 {
        if phase == "listening" || phase == "reviewing" {
            return 10
        }
        phase = "listening"
        liveTranscript = ""
        reviewTranscript = ""
        lastError = nil
        return 0
    }

    func dictationAppendPartial(_ text: String) -> UInt8 {
        guard phase == "listening" else {
            return 11
        }
        liveTranscript = text
        return 0
    }

    func dictationFinalizeReview(_ text: String) -> UInt8 {
        guard phase == "listening" else {
            return 11
        }
        liveTranscript = ""
        reviewTranscript = text
        phase = "reviewing"
        return 0
    }

    func dictationConfirm() -> UInt8 {
        guard phase == "reviewing" else {
            return 12
        }
        phase = "confirmed"
        appendDomainAndSignal(
            eventName: "dictation_review_confirmed",
            signalAction: "commit_pending_tool_invocations",
            reason: "dictation_review_confirmed"
        )
        return 0
    }

    func dictationCancel() -> UInt8 {
        guard phase == "listening" || phase == "reviewing" else {
            return 13
        }
        let wasReviewing = phase == "reviewing"
        phase = "cancelled"
        liveTranscript = ""
        reviewTranscript = ""

        if wasReviewing {
            appendDomainAndSignal(
                eventName: "dictation_review_cancelled",
                signalAction: "abort_pending_tool_invocations",
                reason: "dictation_review_cancelled"
            )
        }

        return 0
    }

    func dictationFail(_ message: String) -> UInt8 {
        phase = "failed"
        lastError = message
        return 0
    }

    func commandClassifyJSON(_ utterance: String) -> String {
        let normalized = utterance.lowercased()
        if normalized.contains("note") || normalized.contains("notiz") {
            return "{\"kind\":\"save_note\",\"summary\":\"Notiz speichern\",\"confidence_percent\":70,\"requires_confirmation\":true,\"arguments\":{\"move_destination\":null,\"rename_target\":null,\"timer_duration\":null}}"
        }
        return "{\"kind\":\"unknown\",\"summary\":\"unsupported\",\"confidence_percent\":0,\"requires_confirmation\":false,\"arguments\":{\"move_destination\":null,\"rename_target\":null,\"timer_duration\":null}}"
    }

    func commandSafetyJSON(_ utterance: String) -> String {
        let normalized = utterance.lowercased()
        if normalized.contains("note") || normalized.contains("notiz") {
            return "{\"decision\":\"require_confirmation\",\"destructive\":false,\"reason\":\"explicit_user_confirmation_required\"}"
        }
        return "{\"decision\":\"reject\",\"destructive\":false,\"reason\":\"unknown_intent\"}"
    }

    func coreEventsSinceJSON(lastSeenEventID: UInt64, limit: UInt16) -> String {
        _ = lastSeenEventID
        _ = limit
        return "{\"events\":[]}"
    }

    func coreEventsClear() -> UInt8 {
        0
    }

    func domainEventsSinceJSON(lastSeenEventID: UInt64, limit: UInt16) -> String {
        let events = domainEvents
            .filter { $0.id > lastSeenEventID }
            .prefix(Int(limit == 0 ? 50 : limit))
        let payload = DomainEventsPayload(events: Array(events))
        return encodeJSON(payload) ?? "{\"events\":[]}"
    }

    func toolRuntimeSignalsSinceJSON(lastSeenSignalID: UInt64, limit: UInt16) -> String {
        let signals = toolSignals
            .filter { $0.id > lastSeenSignalID }
            .prefix(Int(limit == 0 ? 50 : limit))
        let payload = ToolSignalsPayload(signals: Array(signals))
        return encodeJSON(payload) ?? "{\"signals\":[]}"
    }

    func domainEventsClear() -> UInt8 {
        domainEvents.removeAll()
        toolSignals.removeAll()
        nextDomainEventID = 1
        nextToolSignalID = 1
        return 0
    }

    func reportCoreErrorEvent(source: String, code: String, message: String) -> UInt8 {
        _ = source
        _ = code
        _ = message
        return 0
    }

    func reportCorePermissionEvent(source: String, permission: String, status: String, detail: String) -> UInt8 {
        _ = source
        _ = permission
        _ = status
        _ = detail
        return 0
    }

    func reportCoreTelemetryEvent(
        source: String,
        category: String,
        action: String,
        status: String,
        contextJSON: String,
        valueMs: UInt32
    ) -> UInt8 {
        _ = source
        _ = category
        _ = action
        _ = status
        _ = contextJSON
        _ = valueMs
        return 0
    }

    func sttRouteJSON(
        preferenceMode: UInt8,
        sensitiveModeEnabled: Bool,
        networkAvailable: Bool,
        utteranceDurationMs: UInt32
    ) -> String {
        _ = preferenceMode
        _ = sensitiveModeEnabled
        _ = networkAvailable
        _ = utteranceDurationMs
        return "{\"provider\":\"apple_speech_recognizer\",\"reason\":\"test\"}"
    }

    private func appendDomainAndSignal(eventName: String, signalAction: String, reason: String) {
        let event = DomainEventRecord(
            id: nextDomainEventID,
            timestamp_ms: UInt64(Date().timeIntervalSince1970 * 1_000),
            name: eventName,
            source: "test.core_bridge",
            phase_before: "reviewing",
            review_transcript_length: UInt32(reviewTranscript.count)
        )
        nextDomainEventID += 1
        domainEvents.append(event)

        let signal = ToolRuntimeSignalRecord(
            id: nextToolSignalID,
            timestamp_ms: UInt64(Date().timeIntervalSince1970 * 1_000),
            action: signalAction,
            reason: reason,
            origin_domain_event_id: event.id
        )
        nextToolSignalID += 1
        toolSignals.append(signal)
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(value),
            let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return text
    }
}

private struct DomainEventsPayload: Encodable {
    let events: [DomainEventRecord]
}

private struct DomainEventRecord: Encodable {
    let id: UInt64
    let timestamp_ms: UInt64
    let name: String
    let source: String
    let phase_before: String
    let review_transcript_length: UInt32
}

private struct ToolSignalsPayload: Encodable {
    let signals: [ToolRuntimeSignalRecord]
}

private struct ToolRuntimeSignalRecord: Encodable {
    let id: UInt64
    let timestamp_ms: UInt64
    let action: String
    let reason: String
    let origin_domain_event_id: UInt64
}

private final class FakeAudioCaptureAdapter: AudioCapturing {
    var isCapturing: Bool = false
    private let durationMs: UInt32

    init(durationMs: UInt32 = 1_600) {
        self.durationMs = durationMs
    }

    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        completion(true)
    }

    func startCapture(levelHandler: @escaping (Float) -> Void) throws {
        isCapturing = true
        levelHandler(0.3)
    }

    func stopCapture() -> AudioCaptureResult? {
        guard isCapturing else {
            return nil
        }
        isCapturing = false
        return AudioCaptureResult(
            sampleRate: 16_000,
            channelCount: 1,
            frameCount: Int(durationMs * 16),
            durationMs: durationMs,
            averagePower: 0.2,
            peakPower: 0.5
        )
    }
}

private final class NoopHotkeyAdapter: HotkeyListening {
    var isListening: Bool = false

    func startListening(onTrigger: @escaping () -> Void) {
        _ = onTrigger
        isListening = true
    }

    func stopListening() {
        isListening = false
    }
}

private struct ImmediateSuccessSTTAdapter: STTTranscribing {
    let providerIdentifier: String
    let transcript: String

    init(transcript: String, providerIdentifier: String = "apple_speech_recognizer") {
        self.transcript = transcript
        self.providerIdentifier = providerIdentifier
    }

    func transcribe(
        capture: AudioCaptureResult,
        locale: String,
        completion: @escaping (Result<STTTranscriptResult, Error>) -> Void
    ) {
        _ = capture
        _ = locale
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(30)) {
            completion(
                .success(
                    STTTranscriptResult(
                        provider: providerIdentifier,
                        transcript: transcript,
                        confidencePercent: 81,
                        latencyMs: 35
                    )
                )
            )
        }
    }
}

private struct SuccessfulTextInjectionAdapter: TextInjecting {
    func inject(text: String, strategy: TextInjectionStrategy, preferClipboardFor bundleIdentifier: String?) -> TextInjectionResult {
        _ = text
        _ = strategy
        _ = bundleIdentifier
        return TextInjectionResult(
            disposition: .injected,
            method: .accessibility,
            detail: "test injection success"
        )
    }
}

private final class InMemoryTelemetryLogger: StructuredTelemetryLogging {
    var logFilePath: String {
        "/tmp/syntic-test-telemetry.ndjson"
    }

    private(set) var events: [StructuredTelemetryEvent] = []

    func append(_ event: StructuredTelemetryEvent) {
        events.append(event)
    }
}
