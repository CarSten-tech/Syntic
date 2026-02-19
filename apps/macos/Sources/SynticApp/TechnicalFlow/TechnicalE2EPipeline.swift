import AppKit
import Foundation

@MainActor
final class TechnicalE2EPipeline: ObservableObject {
    @Published private(set) var phase = "idle"
    @Published private(set) var isHotkeyListening = false
    @Published private(set) var latestAudioLevel: Float = 0
    @Published private(set) var latestRouteJSON = "{}"
    @Published private(set) var latestTranscript = ""
    @Published private(set) var latestInjectionSummary = "-"
    @Published private(set) var coreEventsJSON = "{\"events\":[]}"
    @Published private(set) var domainEventsJSON = "{\"events\":[]}"
    @Published private(set) var toolRuntimeSignalsJSON = "{\"signals\":[]}"
    @Published private(set) var toolRuntimeQueueJSON = "{\"pending\":[],\"running\":[],\"completed\":[],\"cancelled\":[],\"failed\":[]}"
    @Published private(set) var toolRuntimeExecutionLogPath = "-"
    @Published private(set) var dictationStateJSON = "{}"
    @Published private(set) var telemetryLogPath = "-"
    @Published private(set) var logs: [String] = []

    @Published var networkAvailable = true

    private let coreBridge: SynticCoreVersionProviding
    private let settingsController: AppSettingsController
    private let sessionHistoryController: SessionHistoryController
    private let audioAdapter: AudioCapturing
    private let hotkeyAdapter: HotkeyListening
    private let localSttAdapter: STTTranscribing
    private let cloudSttAdapter: STTTranscribing
    private let textInjectionAdapter: TextInjecting
    private let toolExecutor: ToolExecuting
    private let telemetryLogger: StructuredTelemetryLogging

    private var isTranscribing = false
    private var activeSessionStartedAtMs: UInt64?
    private var activeRouteProvider = "unknown"
    private var lastSeenDomainEventID: UInt64 = 0
    private var lastSeenToolRuntimeSignalID: UInt64 = 0
    private var nextToolInvocationOrdinal: UInt64 = 1
    private var pendingToolInvocations: [ToolInvocation] = []
    private var runningToolInvocationTasks: [String: Task<Void, Never>] = [:]
    private var runningToolInvocationStartedAtMs: [String: UInt64] = [:]
    private var completedToolInvocationIDs: [String] = []
    private var cancelledToolInvocationIDs: [String] = []
    private var failedToolInvocationIDs: [String] = []

    init(
        coreBridge: SynticCoreVersionProviding,
        settingsController: AppSettingsController,
        sessionHistoryController: SessionHistoryController,
        audioAdapter: AudioCapturing = MacOSAudioCaptureAdapter(),
        hotkeyAdapter: HotkeyListening = MacOSGlobalHotkeyAdapter(),
        localSttAdapter: STTTranscribing = LocalStubSTTAdapter(),
        cloudSttAdapter: STTTranscribing = CloudStubSTTAdapter(),
        textInjectionAdapter: TextInjecting = MacOSTextInjectionAdapter(),
        toolExecutor: ToolExecuting = FileBackedToolExecutor(),
        telemetryLogger: StructuredTelemetryLogging = NDJSONTelemetryLogger()
    ) {
        self.coreBridge = coreBridge
        self.settingsController = settingsController
        self.sessionHistoryController = sessionHistoryController
        self.audioAdapter = audioAdapter
        self.hotkeyAdapter = hotkeyAdapter
        self.localSttAdapter = localSttAdapter
        self.cloudSttAdapter = cloudSttAdapter
        self.textInjectionAdapter = textInjectionAdapter
        self.toolExecutor = toolExecutor
        self.telemetryLogger = telemetryLogger

        dictationStateJSON = coreBridge.dictationStateJSON()
        telemetryLogPath = telemetryLogger.logFilePath
        toolRuntimeExecutionLogPath = toolExecutor.executionLogPath
        _ = coreBridge.coreEventsClear()
        _ = coreBridge.domainEventsClear()
        refreshCoreEventsFeed()
        refreshDomainAndToolRuntimeFeeds()
        refreshToolRuntimeQueueSnapshot()
        emitTelemetry(
            category: "e2e_flow",
            action: "pipeline_initialized",
            status: "ok",
            context: [
                "settings_locale": settingsController.locale.rawValue,
                "settings_routing_mode": settingsController.routingMode.rawValue,
                "settings_sensitive_mode": settingsController.sensitiveModeEnabled ? "true" : "false",
            ]
        )
        appendLog("Technical E2E pipeline initialized.")
    }

    deinit {
        for task in runningToolInvocationTasks.values {
            task.cancel()
        }
        hotkeyAdapter.stopListening()
        _ = audioAdapter.stopCapture()
    }

    var reviewActionsEnabled: Bool {
        phase == "reviewing"
    }

    var recentLogText: String {
        logs.suffix(10).joined(separator: "\n")
    }

    var hasUndoCandidate: Bool {
        sessionHistoryController.hasUndoCandidate
    }

    var sessionHistoryPath: String {
        sessionHistoryController.historyFilePath
    }

    func toggleHotkeyListener() {
        if isHotkeyListening {
            hotkeyAdapter.stopListening()
            isHotkeyListening = false
            emitTelemetry(category: "hotkey", action: "listener_stopped", status: "ok", context: [:])
            appendLog("Hotkey listener stopped.")
            return
        }

        hotkeyAdapter.startListening { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleHotkeyTrigger(source: "hotkey")
            }
        }

        isHotkeyListening = true
        emitTelemetry(category: "hotkey", action: "listener_started", status: "ok", context: ["definition": "option_space"])
        appendLog("Hotkey listener started (Option+Space).")
    }

    func triggerHotkeyAction() {
        handleHotkeyTrigger(source: "manual")
    }

    func confirmReview() {
        let confirmedTranscript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !confirmedTranscript.isEmpty else {
            fail("review_confirm_without_transcript")
            return
        }

        setPhase("injecting", trigger: "confirm_review")
        let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let injectionResult = textInjectionAdapter.inject(
            text: confirmedTranscript,
            strategy: .accessibilityFirst,
            preferClipboardFor: frontmostBundleIdentifier
        )

        latestInjectionSummary =
            "disposition=\(describe(injectionResult.disposition)), method=\(injectionResult.method.rawValue), bundle=\(frontmostBundleIdentifier ?? "unknown")"
        appendLog("Injection result: \(latestInjectionSummary). \(injectionResult.detail)")
        emitTelemetry(
            category: "injection",
            action: "result",
            status: injectionResult.disposition == .failed ? "failed" : "ok",
            context: [
                "disposition": describe(injectionResult.disposition),
                "method": injectionResult.method.rawValue,
                "target_bundle": frontmostBundleIdentifier ?? "unknown",
            ]
        )

        if injectionResult.detail.contains("Accessibility-Berechtigung fehlt.") {
            reportCorePermissionEvent(
                source: "macos.text_injection",
                permission: "accessibility",
                status: "denied",
                detail: injectionResult.detail
            )
        }

        if injectionResult.disposition == .failed {
            fail("text_injection_failed")
            return
        }

        let confirmStatus = coreBridge.dictationConfirm()
        guard confirmStatus == 0 else {
            fail("dictation_confirm_failed_status_\(confirmStatus)")
            return
        }

        refreshDomainAndToolRuntimeFeeds()

        persistSessionRecord(
            outcome: .confirmed,
            transcript: confirmedTranscript,
            errorCode: nil,
            injectionDisposition: mapInjectionDisposition(injectionResult.disposition)
        )

        _ = coreBridge.dictationReset()
        setPhase("idle", trigger: "confirm_review_completed")
        refreshDictationState()
        emitTelemetry(
            category: "review",
            action: "confirmed",
            status: "ok",
            context: [
                "transcript_length": "\(confirmedTranscript.count)",
            ]
        )
        appendLog("Review confirmed and state reset.")
    }

    func cancelReview() {
        let cancelStatus = coreBridge.dictationCancel()
        guard cancelStatus == 0 else {
            fail("dictation_cancel_failed_status_\(cancelStatus)")
            return
        }

        refreshDomainAndToolRuntimeFeeds()

        persistSessionRecord(
            outcome: .cancelled,
            transcript: latestTranscript,
            errorCode: nil,
            injectionDisposition: nil
        )

        _ = coreBridge.dictationReset()
        setPhase("idle", trigger: "cancel_review_completed")
        refreshDictationState()
        emitTelemetry(category: "review", action: "cancelled", status: "ok", context: [:])
        appendLog("Review canceled and state reset.")
    }

    func undoLastConfirmedForReview() {
        guard let restoredRecord = sessionHistoryController.markLastConfirmedAsUndone() else {
            appendLog("Undo skipped: no confirmed session available.")
            emitTelemetry(category: "undo", action: "restore_requested", status: "degraded", context: ["reason": "no_candidate"])
            return
        }

        _ = coreBridge.dictationReset()
        let startStatus = coreBridge.dictationStart()
        let reviewStatus = coreBridge.dictationFinalizeReview(restoredRecord.transcript)
        guard startStatus == 0, reviewStatus == 0 else {
            fail("undo_restore_failed_start=\(startStatus)_review=\(reviewStatus)")
            return
        }

        latestTranscript = restoredRecord.transcript
        activeSessionStartedAtMs = Self.nowMs()
        activeRouteProvider = restoredRecord.routeProvider
        setPhase("reviewing", trigger: "undo_last_confirmed")
        enqueuePendingToolInvocation(
            transcript: restoredRecord.transcript,
            origin: "undo_restore"
        )
        refreshDictationState()
        emitTelemetry(
            category: "undo",
            action: "restore_last_confirmed",
            status: "ok",
            context: [
                "restored_session_id": restoredRecord.id,
                "restored_provider": restoredRecord.routeProvider,
                "transcript_length": "\(restoredRecord.transcript.count)",
            ]
        )
        appendLog("Undo restored confirmed transcript into review state.")
    }

    private func handleHotkeyTrigger(source: String) {
        if isTranscribing {
            emitTelemetry(
                category: "hotkey",
                action: "trigger_ignored",
                status: "degraded",
                context: ["source": source, "reason": "transcribing_in_progress"]
            )
            appendLog("Trigger (\(source)) ignored while transcribing.")
            return
        }

        if phase == "listening" {
            stopListeningAndTranscribe(triggerSource: source)
        } else {
            startListening(triggerSource: source)
        }
    }

    private func startListening(triggerSource: String) {
        _ = coreBridge.dictationReset()
        let startStatus = coreBridge.dictationStart()
        guard startStatus == 0 else {
            fail("dictation_start_failed_status_\(startStatus)")
            return
        }

        latestInjectionSummary = "-"
        activeSessionStartedAtMs = Self.nowMs()
        activeRouteProvider = "unknown"
        emitTelemetry(
            category: "dictation",
            action: "start_requested",
            status: "ok",
            context: ["trigger_source": triggerSource]
        )

        audioAdapter.requestPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                if !granted {
                    self.reportCorePermissionEvent(
                        source: "macos.audio",
                        permission: "microphone",
                        status: "denied",
                        detail: "requestPermission callback returned false"
                    )
                    self.emitTelemetry(
                        category: "permission",
                        action: "microphone_request",
                        status: "denied",
                        context: [:]
                    )
                    self.fail("audio_permission_denied")
                    return
                }

                self.reportCorePermissionEvent(
                    source: "macos.audio",
                    permission: "microphone",
                    status: "granted",
                    detail: "requestPermission callback returned true"
                )
                self.emitTelemetry(
                    category: "permission",
                    action: "microphone_request",
                    status: "granted",
                    context: [:]
                )

                do {
                    try self.audioAdapter.startCapture { [weak self] level in
                        Task { @MainActor [weak self] in
                            self?.latestAudioLevel = level
                        }
                    }
                } catch {
                    self.fail("audio_capture_start_failed")
                    return
                }

                self.setPhase("listening", trigger: "audio_capture_started")
                self.refreshDictationState()
                self.appendLog("Listening started via \(triggerSource) trigger.")
            }
        }
    }

    private func stopListeningAndTranscribe(triggerSource: String) {
        guard let captureResult = audioAdapter.stopCapture() else {
            fail("audio_capture_stop_failed")
            return
        }

        latestAudioLevel = 0
        setPhase("transcribing", trigger: "listening_stopped", valueMs: captureResult.durationMs)
        isTranscribing = true

        latestRouteJSON = coreBridge.sttRouteJSON(
            preferenceMode: settingsController.routingMode.ffiPreferenceMode,
            sensitiveModeEnabled: settingsController.sensitiveModeEnabled,
            networkAvailable: networkAvailable,
            utteranceDurationMs: captureResult.durationMs
        )

        let selectedProvider = parseProviderIdentifier(from: latestRouteJSON)
        let selectedAdapter = selectedProvider == cloudSttAdapter.providerIdentifier ? cloudSttAdapter : localSttAdapter
        activeRouteProvider = selectedAdapter.providerIdentifier

        emitTelemetry(
            category: "stt_routing",
            action: "provider_selected",
            status: "ok",
            context: [
                "selected_provider": selectedAdapter.providerIdentifier,
                "route_payload": latestRouteJSON,
                "network_available": networkAvailable ? "true" : "false",
                "sensitive_mode": settingsController.sensitiveModeEnabled ? "true" : "false",
                "routing_mode": settingsController.routingMode.rawValue,
            ],
            valueMs: captureResult.durationMs
        )

        appendLog(
            "Listening stopped via \(triggerSource). Routing to \(selectedAdapter.providerIdentifier), duration=\(captureResult.durationMs)ms."
        )

        selectedAdapter.transcribe(capture: captureResult, locale: settingsController.locale.rawValue) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.completeTranscription(result)
            }
        }
    }

    private func completeTranscription(_ result: Result<STTTranscriptResult, Error>) {
        isTranscribing = false

        switch result {
        case let .failure(error):
            emitTelemetry(
                category: "stt",
                action: "transcription_failed",
                status: "failed",
                context: ["error": error.localizedDescription]
            )
            fail("stt_transcription_failed_\(error.localizedDescription)")

        case let .success(transcriptResult):
            latestTranscript = transcriptResult.transcript

            let partialStatus = coreBridge.dictationAppendPartial(transcriptResult.transcript)
            let reviewStatus = coreBridge.dictationFinalizeReview(transcriptResult.transcript)

            if partialStatus != 0 || reviewStatus != 0 {
                fail("dictation_review_transition_failed_partial=\(partialStatus)_review=\(reviewStatus)")
                return
            }

            setPhase("reviewing", trigger: "transcription_completed", valueMs: transcriptResult.latencyMs)
            enqueuePendingToolInvocation(
                transcript: transcriptResult.transcript,
                origin: "transcription_completed"
            )
            refreshDictationState()
            emitTelemetry(
                category: "stt",
                action: "transcription_completed",
                status: "ok",
                context: [
                    "provider": transcriptResult.provider,
                    "confidence_percent": "\(transcriptResult.confidencePercent)",
                    "transcript_length": "\(transcriptResult.transcript.count)",
                ],
                valueMs: transcriptResult.latencyMs
            )
            appendLog(
                "Transcript ready from \(transcriptResult.provider), confidence=\(transcriptResult.confidencePercent)% latency=\(transcriptResult.latencyMs)ms."
            )
        }
    }

    private func fail(_ reason: String) {
        abortQueuedAndRunningToolInvocations(reason: "pipeline_failed_\(reason)", originDomainEventID: 0)
        _ = coreBridge.dictationFail(reason)
        persistSessionRecord(
            outcome: .failed,
            transcript: latestTranscript,
            errorCode: reason,
            injectionDisposition: nil
        )
        reportCoreErrorEvent(
            source: "macos.technical_e2e",
            code: reason,
            message: "Technical E2E flow failed"
        )
        setPhase("failed", trigger: "failure", status: "error")
        isTranscribing = false
        refreshDictationState()
        emitTelemetry(
            category: "e2e_flow",
            action: "failed",
            status: "error",
            context: ["reason": reason]
        )
        appendLog("Flow failed: \(reason)")
    }

    private func refreshDictationState() {
        dictationStateJSON = coreBridge.dictationStateJSON()
    }

    private func parseProviderIdentifier(from routeJSON: String) -> String {
        guard
            let data = routeJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let provider = object["provider"] as? String
        else {
            return localSttAdapter.providerIdentifier
        }

        return provider
    }

    private func describe(_ disposition: TextInjectionDisposition) -> String {
        switch disposition {
        case .injected:
            return "injected"
        case .clipboardFallback:
            return "clipboard_fallback"
        case .failed:
            return "failed"
        }
    }

    private func appendLog(_ message: String) {
        logs.append("\(Self.timestampFormatter.string(from: Date())) \(message)")
        if logs.count > 80 {
            logs.removeFirst(logs.count - 80)
        }
    }

    private func reportCoreErrorEvent(source: String, code: String, message: String) {
        let status = coreBridge.reportCoreErrorEvent(source: source, code: code, message: message)
        if status != 0 {
            appendLog("Core error event report failed: status=\(status)")
        }
        refreshCoreEventsFeed()
    }

    private func reportCorePermissionEvent(
        source: String,
        permission: String,
        status: String,
        detail: String
    ) {
        let reportStatus = coreBridge.reportCorePermissionEvent(
            source: source,
            permission: permission,
            status: status,
            detail: detail
        )
        if reportStatus != 0 {
            appendLog("Core permission event report failed: status=\(reportStatus)")
        }
        refreshCoreEventsFeed()
    }

    private func refreshCoreEventsFeed() {
        coreEventsJSON = coreBridge.coreEventsSinceJSON(lastSeenEventID: 0, limit: 64)
    }

    private func refreshDomainAndToolRuntimeFeeds() {
        let domainPayload = coreBridge.domainEventsSinceJSON(
            lastSeenEventID: lastSeenDomainEventID,
            limit: 64
        )
        domainEventsJSON = domainPayload
        if let domainEvents = decodeDomainEvents(from: domainPayload) {
            for domainEvent in domainEvents {
                lastSeenDomainEventID = max(lastSeenDomainEventID, domainEvent.id)
                appendLog(
                    "Domain event consumed: id=\(domainEvent.id), name=\(domainEvent.name), source=\(domainEvent.source)."
                )
            }
        }

        let toolSignalsPayload = coreBridge.toolRuntimeSignalsSinceJSON(
            lastSeenSignalID: lastSeenToolRuntimeSignalID,
            limit: 64
        )
        toolRuntimeSignalsJSON = toolSignalsPayload
        if let toolSignals = decodeToolRuntimeSignals(from: toolSignalsPayload) {
            for signal in toolSignals {
                lastSeenToolRuntimeSignalID = max(lastSeenToolRuntimeSignalID, signal.id)
                consumeToolRuntimeSignal(signal)
            }
        }
    }

    private func consumeToolRuntimeSignal(_ signal: ToolRuntimeSignalEnvelope) {
        appendLog(
            "Tool runtime signal consumed: id=\(signal.id), action=\(signal.action), reason=\(signal.reason)."
        )

        switch signal.action {
        case "abort_pending_tool_invocations":
            abortQueuedAndRunningToolInvocations(
                reason: signal.reason,
                originDomainEventID: signal.originDomainEventID
            )
        case "commit_pending_tool_invocations":
            startQueuedToolInvocations(
                reason: signal.reason,
                originDomainEventID: signal.originDomainEventID
            )
        default:
            emitTelemetry(
                category: "tool_runtime",
                action: "signal_unknown",
                status: "degraded",
                context: [
                    "signal_id": "\(signal.id)",
                    "action": signal.action,
                    "reason": signal.reason,
                    "origin_domain_event_id": "\(signal.originDomainEventID)",
                ]
            )
        }
    }

    private func enqueuePendingToolInvocation(transcript: String, origin: String) {
        let normalizedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTranscript.isEmpty else {
            return
        }

        let invocationID = "tool-\(nextToolInvocationOrdinal)"
        nextToolInvocationOrdinal += 1

        let intentPayload = decodeCommandIntent(from: coreBridge.commandClassifyJSON(normalizedTranscript))
            ?? CommandIntentPayload.unknown
        let safetyPayload = decodeCommandSafety(from: coreBridge.commandSafetyJSON(normalizedTranscript))
            ?? CommandSafetyPayload.rejectedUnknown

        pendingToolInvocations.append(
            ToolInvocation(
                id: invocationID,
                transcript: normalizedTranscript,
                origin: origin,
                queuedAtMs: Self.nowMs(),
                intentKind: intentPayload.kind,
                intentSummary: intentPayload.summary,
                confidencePercent: intentPayload.confidencePercent,
                safetyDecision: safetyPayload.decision,
                destructive: safetyPayload.destructive,
                safetyReason: safetyPayload.reason
            )
        )

        appendLog("Tool invocation queued: id=\(invocationID), origin=\(origin).")
        emitTelemetry(
            category: "tool_runtime",
            action: "invocation_queued",
            status: "ok",
            context: [
                "invocation_id": invocationID,
                "origin": origin,
                "queue_depth": "\(pendingToolInvocations.count)",
                "intent_kind": intentPayload.kind,
                "safety_decision": safetyPayload.decision,
            ]
        )
        refreshToolRuntimeQueueSnapshot()
    }

    private func startQueuedToolInvocations(reason: String, originDomainEventID: UInt64) {
        let pendingCount = pendingToolInvocations.count
        emitTelemetry(
            category: "tool_runtime",
            action: "commit_signal_consumed",
            status: "ok",
            context: [
                "reason": reason,
                "origin_domain_event_id": "\(originDomainEventID)",
                "pending_count": "\(pendingCount)",
            ]
        )

        guard pendingCount > 0 else {
            appendLog("Tool runtime commit signal: no pending invocations.")
            refreshToolRuntimeQueueSnapshot()
            return
        }

        while !pendingToolInvocations.isEmpty {
            let invocation = pendingToolInvocations.removeFirst()
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: 1_200_000_000)
                    try Task.checkCancellation()
                    let executionResult = try self.toolExecutor.execute(
                        plan: ToolExecutionPlan(
                            invocationID: invocation.id,
                            transcript: invocation.transcript,
                            origin: invocation.origin,
                            intentKind: invocation.intentKind,
                            intentSummary: invocation.intentSummary,
                            confidencePercent: invocation.confidencePercent,
                            safetyDecision: invocation.safetyDecision,
                            destructive: invocation.destructive,
                            safetyReason: invocation.safetyReason
                        )
                    )
                    let latencyMs = self.runningInvocationLatencyMs(for: invocation.id)

                    guard self.runningToolInvocationTasks.removeValue(forKey: invocation.id) != nil else {
                        return
                    }
                    self.runningToolInvocationStartedAtMs.removeValue(forKey: invocation.id)
                    self.completedToolInvocationIDs.append(invocation.id)
                    self.appendLog(
                        "Tool invocation completed: id=\(invocation.id), outcome=\(executionResult.outcome.rawValue), detail=\(executionResult.detail)"
                    )
                    self.emitTelemetry(
                        category: "tool_runtime",
                        action: "invocation_completed",
                        status: "ok",
                        context: [
                            "invocation_id": invocation.id,
                            "origin": invocation.origin,
                            "intent_kind": invocation.intentKind,
                            "safety_decision": invocation.safetyDecision,
                            "outcome": executionResult.outcome.rawValue,
                            "artifact_path": executionResult.artifactPath ?? "",
                        ],
                        valueMs: latencyMs
                    )
                    self.refreshToolRuntimeQueueSnapshot()
                } catch is CancellationError {
                    guard self.runningToolInvocationTasks.removeValue(forKey: invocation.id) != nil else {
                        return
                    }
                    self.runningToolInvocationStartedAtMs.removeValue(forKey: invocation.id)
                    self.cancelledToolInvocationIDs.append(invocation.id)
                    self.appendLog("Tool invocation cancelled: id=\(invocation.id).")
                    self.emitTelemetry(
                        category: "tool_runtime",
                        action: "invocation_cancelled",
                        status: "ok",
                        context: [
                            "invocation_id": invocation.id,
                            "origin": invocation.origin,
                        ]
                    )
                    self.refreshToolRuntimeQueueSnapshot()
                } catch {
                    guard self.runningToolInvocationTasks.removeValue(forKey: invocation.id) != nil else {
                        return
                    }
                    self.runningToolInvocationStartedAtMs.removeValue(forKey: invocation.id)
                    self.failedToolInvocationIDs.append(invocation.id)
                    self.appendLog("Tool invocation failed: id=\(invocation.id), error=\(error.localizedDescription).")
                    self.emitTelemetry(
                        category: "tool_runtime",
                        action: "invocation_failed",
                        status: "error",
                        context: [
                            "invocation_id": invocation.id,
                            "origin": invocation.origin,
                            "error": error.localizedDescription,
                        ]
                    )
                    self.refreshToolRuntimeQueueSnapshot()
                }
            }

            runningToolInvocationTasks[invocation.id] = task
            runningToolInvocationStartedAtMs[invocation.id] = Self.nowMs()
            appendLog("Tool invocation started: id=\(invocation.id), origin=\(invocation.origin).")
        }

        refreshToolRuntimeQueueSnapshot()
    }

    private func abortQueuedAndRunningToolInvocations(reason: String, originDomainEventID: UInt64) {
        let pendingCancelledCount = pendingToolInvocations.count
        if pendingCancelledCount > 0 {
            cancelledToolInvocationIDs.append(contentsOf: pendingToolInvocations.map(\.id))
            pendingToolInvocations.removeAll()
        }

        let runningIDs = Array(runningToolInvocationTasks.keys)
        for invocationID in runningIDs {
            runningToolInvocationTasks[invocationID]?.cancel()
            runningToolInvocationTasks.removeValue(forKey: invocationID)
            runningToolInvocationStartedAtMs.removeValue(forKey: invocationID)
            cancelledToolInvocationIDs.append(invocationID)
        }

        emitTelemetry(
            category: "tool_runtime",
            action: "abort_signal_consumed",
            status: "ok",
            context: [
                "reason": reason,
                "origin_domain_event_id": "\(originDomainEventID)",
                "pending_cancelled_count": "\(pendingCancelledCount)",
                "running_cancelled_count": "\(runningIDs.count)",
            ]
        )
        appendLog(
            "Tool runtime abort applied: pending=\(pendingCancelledCount), running=\(runningIDs.count), reason=\(reason)."
        )
        refreshToolRuntimeQueueSnapshot()
    }

    private func runningInvocationLatencyMs(for invocationID: String) -> UInt32? {
        guard let startedAt = runningToolInvocationStartedAtMs[invocationID] else {
            return nil
        }
        let now = Self.nowMs()
        if now <= startedAt {
            return 0
        }
        let delta = now - startedAt
        return delta > UInt64(UInt32.max) ? UInt32.max : UInt32(delta)
    }

    private func refreshToolRuntimeQueueSnapshot() {
        let snapshot = ToolRuntimeQueueSnapshot(
            pending: pendingToolInvocations.map {
                ToolInvocationSnapshot(
                    id: $0.id,
                    origin: $0.origin,
                    transcript_length: $0.transcript.count,
                    queued_at_ms: $0.queuedAtMs,
                    intent_kind: $0.intentKind,
                    safety_decision: $0.safetyDecision,
                    destructive: $0.destructive
                )
            },
            running: runningToolInvocationTasks.keys.sorted(),
            completed: completedToolInvocationIDs.suffix(20).map { $0 },
            cancelled: cancelledToolInvocationIDs.suffix(20).map { $0 },
            failed: failedToolInvocationIDs.suffix(20).map { $0 }
        )
        guard
            let data = try? JSONEncoder().encode(snapshot),
            let value = String(data: data, encoding: .utf8)
        else {
            toolRuntimeQueueJSON = "{\"pending\":[],\"running\":[],\"completed\":[],\"cancelled\":[],\"failed\":[]}"
            return
        }
        toolRuntimeQueueJSON = value
    }

    private func decodeDomainEvents(from payload: String) -> [DomainEventEnvelope]? {
        guard let data = payload.data(using: .utf8) else {
            return nil
        }
        let decoded = try? JSONDecoder().decode(DomainEventsPayload.self, from: data)
        return decoded?.events
    }

    private func decodeCommandIntent(from payload: String) -> CommandIntentPayload? {
        guard let data = payload.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(CommandIntentPayload.self, from: data)
    }

    private func decodeCommandSafety(from payload: String) -> CommandSafetyPayload? {
        guard let data = payload.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(CommandSafetyPayload.self, from: data)
    }

    private func decodeToolRuntimeSignals(from payload: String) -> [ToolRuntimeSignalEnvelope]? {
        guard let data = payload.data(using: .utf8) else {
            return nil
        }
        let decoded = try? JSONDecoder().decode(ToolRuntimeSignalsPayload.self, from: data)
        return decoded?.signals
    }

    private func setPhase(
        _ newPhase: String,
        trigger: String,
        status: String = "ok",
        valueMs: UInt32? = nil
    ) {
        let previousPhase = phase
        phase = newPhase
        emitTelemetry(
            category: "e2e_phase",
            action: "transition",
            status: status,
            context: [
                "from_phase": previousPhase,
                "to_phase": newPhase,
                "trigger": trigger,
            ],
            valueMs: valueMs
        )
    }

    private func emitTelemetry(
        category: String,
        action: String,
        status: String,
        context: [String: String],
        valueMs: UInt32? = nil
    ) {
        let mergedContext = context.merging(["phase": phase], uniquingKeysWith: { current, _ in current })
        telemetryLogger.append(
            StructuredTelemetryEvent(
                source: "macos.technical_e2e",
                category: category,
                action: action,
                status: status,
                context: mergedContext,
                valueMs: valueMs
            )
        )

        let coreStatus = coreBridge.reportCoreTelemetryEvent(
            source: "macos.technical_e2e",
            category: category,
            action: action,
            status: status,
            contextJSON: serializeContextJSON(mergedContext),
            valueMs: valueMs ?? 0
        )
        if coreStatus != 0 {
            appendLog("Core telemetry event report failed: status=\(coreStatus)")
        }
        refreshCoreEventsFeed()
    }

    private func serializeContextJSON(_ context: [String: String]) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: context, options: [.sortedKeys]),
            let value = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return value
    }

    private func persistSessionRecord(
        outcome: SessionOutcome,
        transcript: String,
        errorCode: String?,
        injectionDisposition: SessionInjectionDisposition?
    ) {
        sessionHistoryController.record(
            outcome: outcome,
            transcript: transcript,
            locale: settingsController.locale.rawValue,
            routeProvider: activeRouteProvider,
            durationMs: currentSessionDurationMs(),
            errorCode: errorCode,
            injectionDisposition: injectionDisposition
        )
        activeSessionStartedAtMs = nil
        activeRouteProvider = "unknown"
    }

    private func currentSessionDurationMs() -> UInt32? {
        guard let startedAt = activeSessionStartedAtMs else {
            return nil
        }
        let now = Self.nowMs()
        if now <= startedAt {
            return 0
        }
        let delta = now - startedAt
        return delta > UInt64(UInt32.max) ? UInt32.max : UInt32(delta)
    }

    private func mapInjectionDisposition(_ disposition: TextInjectionDisposition) -> SessionInjectionDisposition {
        switch disposition {
        case .injected:
            return .injected
        case .clipboardFallback:
            return .clipboardFallback
        case .failed:
            return .failed
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func nowMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }
}

private struct ToolInvocation {
    let id: String
    let transcript: String
    let origin: String
    let queuedAtMs: UInt64
    let intentKind: String
    let intentSummary: String
    let confidencePercent: UInt8
    let safetyDecision: String
    let destructive: Bool
    let safetyReason: String
}

private struct ToolRuntimeQueueSnapshot: Codable {
    let pending: [ToolInvocationSnapshot]
    let running: [String]
    let completed: [String]
    let cancelled: [String]
    let failed: [String]
}

private struct ToolInvocationSnapshot: Codable {
    let id: String
    let origin: String
    let transcript_length: Int
    let queued_at_ms: UInt64
    let intent_kind: String
    let safety_decision: String
    let destructive: Bool
}

private struct DomainEventsPayload: Decodable {
    let events: [DomainEventEnvelope]
}

private struct DomainEventEnvelope: Decodable {
    let id: UInt64
    let name: String
    let source: String
    let phaseBefore: String
    let reviewTranscriptLength: UInt32

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case source
        case phaseBefore = "phase_before"
        case reviewTranscriptLength = "review_transcript_length"
    }
}

private struct ToolRuntimeSignalsPayload: Decodable {
    let signals: [ToolRuntimeSignalEnvelope]
}

private struct ToolRuntimeSignalEnvelope: Decodable {
    let id: UInt64
    let action: String
    let reason: String
    let originDomainEventID: UInt64

    enum CodingKeys: String, CodingKey {
        case id
        case action
        case reason
        case originDomainEventID = "origin_domain_event_id"
    }
}

private struct CommandIntentPayload: Decodable {
    let kind: String
    let summary: String
    let confidencePercent: UInt8
    let requiresConfirmation: Bool

    enum CodingKeys: String, CodingKey {
        case kind
        case summary
        case confidencePercent = "confidence_percent"
        case requiresConfirmation = "requires_confirmation"
    }

    static let unknown = CommandIntentPayload(
        kind: "unknown",
        summary: "Intent parse failed",
        confidencePercent: 0,
        requiresConfirmation: false
    )
}

private struct CommandSafetyPayload: Decodable {
    let decision: String
    let destructive: Bool
    let reason: String

    static let rejectedUnknown = CommandSafetyPayload(
        decision: "reject",
        destructive: false,
        reason: "safety_parse_failed"
    )
}
