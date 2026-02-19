import AppKit
import Foundation

@MainActor
final class TechnicalE2EPipeline: ObservableObject {
    @Published private(set) var phase = "idle"
    @Published private(set) var isHotkeyListening = false
    @Published private(set) var hotkeyDefinition = "-"
    @Published private(set) var hotkeyStatusSummary = "not_started"
    @Published private(set) var hotkeySignalMessage = "Noch kein Hotkey erkannt."
    @Published private(set) var hotkeySignalKind = "idle"
    @Published private(set) var hotkeyDebugStatus = "idle"
    @Published private(set) var latestAudioLevel: Float = 0
    @Published private(set) var latestRouteJSON = "{}"
    @Published private(set) var latestTranscript = ""
    @Published private(set) var latestInjectionSummary = "-"
    @Published private(set) var coreEventsJSON = "{\"events\":[]}"
    @Published private(set) var domainEventsJSON = "{\"events\":[]}"
    @Published private(set) var toolRuntimeSignalsJSON = "{\"signals\":[]}"
    @Published private(set) var coreSessionHistoryJSON = "{\"records\":[]}"
    @Published private(set) var toolRuntimeQueueJSON = "{\"pending\":[],\"running\":[],\"completed\":[],\"cancelled\":[],\"failed\":[]}"
    @Published private(set) var toolRuntimeExecutionLogPath = "-"
    @Published private(set) var dictationStateJSON = "{}"
    @Published private(set) var telemetryLogPath = "-"
    @Published private(set) var coreFeedProjectionPath = "-"
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
    private let coreFeedProjector: CoreFeedProjecting

    private var isTranscribing = false
    private var isStartingCapture = false
    private var shouldAutoConfirmAfterTranscription = false
    private var activeSessionStartedAtMs: UInt64?
    private var activeRouteProvider = "unknown"
    private var capturedInjectionTargetBundleIdentifier: String?
    private var capturedInjectionTargetProcessIdentifier: pid_t?
    private var lastSeenCoreEventID: UInt64 = 0
    private var lastSeenDomainEventID: UInt64 = 0
    private var lastSeenToolRuntimeSignalID: UInt64 = 0
    private var lastSeenSessionHistoryRecordID: UInt64 = 0
    private var nextToolInvocationOrdinal: UInt64 = 1
    private var pendingToolInvocations: [ToolInvocation] = []
    private var runningToolInvocationTasks: [String: Task<Void, Never>] = [:]
    private var runningToolInvocationStartedAtMs: [String: UInt64] = [:]
    private var completedToolInvocationIDs: [String] = []
    private var cancelledToolInvocationIDs: [String] = []
    private var failedToolInvocationIDs: [String] = []
    private var coreEventWindow: [CoreEventEnvelope] = []
    private var domainEventWindow: [DomainEventEnvelope] = []
    private var toolSignalWindow: [ToolRuntimeSignalEnvelope] = []
    private var sessionHistoryWindow: [CoreSessionHistoryRecordEnvelope] = []

    init(
        coreBridge: SynticCoreVersionProviding,
        settingsController: AppSettingsController,
        sessionHistoryController: SessionHistoryController,
        audioAdapter: AudioCapturing = MacOSAudioCaptureAdapter(),
        hotkeyAdapter: HotkeyListening = MacOSGlobalHotkeyAdapter(),
        localSttAdapter: STTTranscribing = AppleSpeechRecognizerSTTAdapter(),
        cloudSttAdapter: STTTranscribing = CloudStubSTTAdapter(),
        textInjectionAdapter: TextInjecting = MacOSTextInjectionAdapter(),
        toolExecutor: ToolExecuting = FileBackedToolExecutor(),
        telemetryLogger: StructuredTelemetryLogging = NDJSONTelemetryLogger(),
        coreFeedProjector: CoreFeedProjecting = NDJSONCoreFeedProjector()
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
        self.coreFeedProjector = coreFeedProjector

        hotkeyDefinition = hotkeyAdapter.supportedHotkeysDescription
        dictationStateJSON = coreBridge.dictationStateJSON()
        telemetryLogPath = telemetryLogger.logFilePath
        coreFeedProjectionPath = coreFeedProjector.logFilePath
        toolRuntimeExecutionLogPath = toolExecutor.executionLogPath
        _ = coreBridge.coreEventsClear()
        _ = coreBridge.domainEventsClear()
        refreshCoreEventsFeed()
        refreshDomainAndToolRuntimeFeeds()
        refreshCoreSessionHistoryFeed()
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
        startHotkeyListenerIfNeeded(startSource: "auto_init")
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
            hotkeyStatusSummary = "stopped"
            emitTelemetry(category: "hotkey", action: "listener_stopped", status: "ok", context: [:])
            appendLog("Hotkey listener stopped.")
            return
        }

        startHotkeyListenerIfNeeded(startSource: "manual_toggle")
    }

    private func startHotkeyListenerIfNeeded(startSource: String) {
        guard !isHotkeyListening else {
            return
        }

        let startResult = hotkeyAdapter.startListening { [weak self] hotkeyLabel in
            Task { @MainActor [weak self] in
                self?.handleHotkeyTrigger(source: "hotkey", hotkeyLabel: hotkeyLabel)
            }
        }

        isHotkeyListening = startResult.started
        hotkeyStatusSummary = startResult.statusSummary
        let listenerStatus = startResult.hasGlobalMonitor ? "ok" : "degraded"
        emitTelemetry(
            category: "hotkey",
            action: "listener_started",
            status: listenerStatus,
            context: [
                "definition": startResult.hotkeySummary,
                "start_source": startSource,
                "global_monitor": startResult.hasGlobalMonitor ? "on" : "off",
                "local_monitor": startResult.hasLocalMonitor ? "on" : "off",
                "accessibility_trusted": startResult.accessibilityTrusted ? "true" : "false",
                "accessibility_prompted": startResult.promptedAccessibility ? "true" : "false",
            ]
        )
        appendLog("Hotkey listener start: \(startResult.statusSummary), source=\(startSource).")

        if !startResult.hasGlobalMonitor {
            appendLog("Global hotkey capture unavailable. Check macOS permissions for Accessibility and Input Monitoring.")
        }
    }

    func triggerHotkeyAction() {
        handleHotkeyTrigger(source: "manual", hotkeyLabel: "Manual Trigger")
    }

    func confirmReview() {
        let confirmedTranscript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !confirmedTranscript.isEmpty else {
            updateHotkeyDebug("confirm_failed empty_transcript")
            fail("review_confirm_without_transcript")
            return
        }

        setPhase("injecting", trigger: "confirm_review")
        let targetContext = resolvedInjectionTargetContext()
        refocusInjectionTargetIfNeeded(targetContext)
        let targetBundleIdentifier = targetContext.bundleIdentifier
        let injectionResult = textInjectionAdapter.inject(
            text: confirmedTranscript,
            strategy: .accessibilityFirst,
            preferClipboardFor: targetBundleIdentifier
        )

        latestInjectionSummary =
            "disposition=\(describe(injectionResult.disposition)), method=\(injectionResult.method.rawValue), bundle=\(targetBundleIdentifier ?? "unknown")"
        updateHotkeyDebug("injection \(latestInjectionSummary) detail=\(injectionResult.detail)")
        if injectionResult.disposition == .clipboardFallback {
            updateHotkeyDebug("clipboard_fallback: falls kein Text erscheint, bitte Cmd+V druecken")
        }
        appendLog("Injection result: \(latestInjectionSummary). \(injectionResult.detail)")
        let injectionTelemetryStatus: String
        switch injectionResult.disposition {
        case .injected:
            injectionTelemetryStatus = "ok"
        case .clipboardFallback:
            injectionTelemetryStatus = "fallback"
        case .failed:
            injectionTelemetryStatus = "failed"
        }
        emitTelemetry(
            category: "injection",
            action: "result",
            status: injectionTelemetryStatus,
            context: [
                "disposition": describe(injectionResult.disposition),
                "method": injectionResult.method.rawValue,
                "target_bundle": targetBundleIdentifier ?? "unknown",
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
        clearCapturedInjectionTargetContext()
        setPhase("idle", trigger: "confirm_review_completed")
        refreshDictationState()
        updateHotkeyDebug("confirm_completed disposition=\(describe(injectionResult.disposition))")
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
        clearCapturedInjectionTargetContext()
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

        let coreUndoStatus = coreBridge.markCoreSessionHistoryLastConfirmedUndone()
        if coreUndoStatus != 0 {
            appendLog("Core session-history undo mirror failed: status=\(coreUndoStatus)")
            emitTelemetry(
                category: "session_history",
                action: "core_undo_mirror",
                status: "degraded",
                context: ["status": "\(coreUndoStatus)"]
            )
        } else {
            refreshCoreSessionHistoryFeed()
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

    private func handleHotkeyTrigger(source: String, hotkeyLabel: String?) {
        let triggerLabel = hotkeyLabel ?? source
        if isStartingCapture {
            markHotkeySignal(kind: "ignored", message: "\(triggerLabel): ignoriert (Start laeuft)")
            updateHotkeyDebug("trigger_ignored reason=capture_start_in_progress source=\(source) label=\(triggerLabel)")
            emitTelemetry(
                category: "hotkey",
                action: "trigger_ignored",
                status: "degraded",
                context: ["source": source, "label": triggerLabel, "reason": "capture_start_in_progress"]
            )
            appendLog("Trigger (\(source)) ignored while capture start is in progress.")
            return
        }

        if isTranscribing {
            markHotkeySignal(kind: "ignored", message: "\(triggerLabel): ignoriert (Transkription laeuft)")
            updateHotkeyDebug("trigger_ignored reason=transcribing_in_progress source=\(source) label=\(triggerLabel)")
            emitTelemetry(
                category: "hotkey",
                action: "trigger_ignored",
                status: "degraded",
                context: ["source": source, "label": triggerLabel, "reason": "transcribing_in_progress"]
            )
            appendLog("Trigger (\(source)) ignored while transcribing.")
            return
        }

        if phase == "listening" {
            markHotkeySignal(kind: "stop", message: "\(triggerLabel): STOP")
            updateHotkeyDebug("trigger_stop source=\(source) label=\(triggerLabel)")
            stopListeningAndTranscribe(triggerSource: source)
        } else {
            markHotkeySignal(kind: "start", message: "\(triggerLabel): START")
            updateHotkeyDebug("trigger_start source=\(source) label=\(triggerLabel)")
            startListening(triggerSource: source)
        }
    }

    private func startListening(triggerSource: String) {
        if isStartingCapture {
            emitTelemetry(
                category: "dictation",
                action: "start_ignored",
                status: "degraded",
                context: ["reason": "capture_start_in_progress"]
            )
            return
        }

        _ = coreBridge.dictationReset()
        shouldAutoConfirmAfterTranscription = false
        captureInjectionTargetContext(triggerSource: triggerSource)
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
        updateHotkeyDebug("start_requested trigger=\(triggerSource)")
        isStartingCapture = true

        audioAdapter.requestPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                if !granted {
                    self.isStartingCapture = false
                    self.updateHotkeyDebug("microphone_permission_denied")
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
                self.updateHotkeyDebug("microphone_permission_granted")

                do {
                    try self.audioAdapter.startCapture { [weak self] level in
                        Task { @MainActor [weak self] in
                            self?.latestAudioLevel = level
                        }
                    }
                } catch {
                    self.isStartingCapture = false
                    self.updateHotkeyDebug("audio_capture_start_failed \(error.localizedDescription)")
                    self.fail("audio_capture_start_failed")
                    return
                }

                self.isStartingCapture = false
                self.setPhase("listening", trigger: "audio_capture_started")
                self.refreshDictationState()
                self.updateHotkeyDebug("listening")
                self.appendLog("Listening started via \(triggerSource) trigger.")
            }
        }
    }

    private func stopListeningAndTranscribe(triggerSource: String) {
        guard let captureResult = audioAdapter.stopCapture() else {
            fail("audio_capture_stop_failed")
            return
        }

        shouldAutoConfirmAfterTranscription = (triggerSource == "hotkey")
        latestAudioLevel = 0
        setPhase("transcribing", trigger: "listening_stopped", valueMs: captureResult.durationMs)
        isTranscribing = true
        updateHotkeyDebug("transcribing duration_ms=\(captureResult.durationMs)")

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
            shouldAutoConfirmAfterTranscription = false
            let sttFailureCode = reportStructuredSTTFailure(error)
            updateHotkeyDebug("stt_failed code=\(sttFailureCode) message=\(error.localizedDescription)")
            if sttFailureCode == "no_speech_detected" {
                _ = coreBridge.dictationReset()
                latestTranscript = ""
                setPhase("idle", trigger: "transcription_empty", status: "degraded")
                refreshDictationState()
                emitTelemetry(
                    category: "stt",
                    action: "transcription_empty",
                    status: "degraded",
                    context: [
                        "provider": activeRouteProvider,
                        "error_code": sttFailureCode,
                    ]
                )
                appendLog("No speech detected by STT provider \(activeRouteProvider); returned to idle.")
                return
            }
            emitTelemetry(
                category: "stt",
                action: "transcription_failed",
                status: "failed",
                context: [
                    "provider": activeRouteProvider,
                    "error_code": sttFailureCode,
                    "error": error.localizedDescription,
                ]
            )
            fail("stt_transcription_failed_\(sttFailureCode)", reportCoreError: false)

        case let .success(transcriptResult):
            latestTranscript = transcriptResult.transcript
            updateHotkeyDebug(
                "stt_ok provider=\(transcriptResult.provider) confidence=\(transcriptResult.confidencePercent) transcript_len=\(transcriptResult.transcript.count)"
            )

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

            if shouldAutoConfirmAfterTranscription {
                shouldAutoConfirmAfterTranscription = false
                updateHotkeyDebug("auto_confirm_requested")
                confirmReview()
            }
        }
    }

    private func reportStructuredSTTFailure(_ error: Error) -> String {
        let source = "macos.stt.\(activeRouteProvider)"
        guard let sttError = error as? STTAdapterError else {
            reportCoreErrorEvent(
                source: source,
                code: "unknown_transcription_error",
                message: error.localizedDescription
            )
            return "unknown_transcription_error"
        }

        switch sttError {
        case .noSpeechDetected:
            reportCoreErrorEvent(
                source: source,
                code: "no_speech_detected",
                message: "No speech detected in capture payload."
            )
            return "no_speech_detected"

        case .missingRecordingFile:
            reportCoreErrorEvent(
                source: source,
                code: "missing_recording_file",
                message: "Capture did not provide a recording file URL for STT."
            )
            return "missing_recording_file"

        case .speechPermissionDenied:
            reportCorePermissionEvent(
                source: source,
                permission: "speech_recognition",
                status: "denied",
                detail: "Speech recognizer authorization is not granted."
            )
            reportCoreErrorEvent(
                source: source,
                code: "speech_permission_denied",
                message: "Speech recognition permission denied."
            )
            emitTelemetry(
                category: "permission",
                action: "speech_recognition_request",
                status: "denied",
                context: ["provider": activeRouteProvider]
            )
            return "speech_permission_denied"

        case .recognizerUnavailable:
            reportCoreErrorEvent(
                source: source,
                code: "recognizer_unavailable",
                message: "Speech recognizer unavailable for locale \(settingsController.locale.rawValue)."
            )
            return "recognizer_unavailable"

        case let .recognitionFailed(detail):
            if detail.lowercased().contains("no speech detected") {
                reportCoreErrorEvent(
                    source: source,
                    code: "no_speech_detected",
                    message: detail
                )
                return "no_speech_detected"
            }
            reportCoreErrorEvent(
                source: source,
                code: "recognition_failed",
                message: detail
            )
            return "recognition_failed"
        }
    }

    private func fail(_ reason: String, reportCoreError: Bool = true) {
        isStartingCapture = false
        shouldAutoConfirmAfterTranscription = false
        hotkeySignalKind = "idle"
        updateHotkeyDebug("failed reason=\(reason)")
        clearCapturedInjectionTargetContext()
        abortQueuedAndRunningToolInvocations(reason: "pipeline_failed_\(reason)", originDomainEventID: 0)
        _ = coreBridge.dictationFail(reason)
        persistSessionRecord(
            outcome: .failed,
            transcript: latestTranscript,
            errorCode: reason,
            injectionDisposition: nil
        )
        if reportCoreError {
            reportCoreErrorEvent(
                source: "macos.technical_e2e",
                code: reason,
                message: "Technical E2E flow failed"
            )
        }
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
        let payload = coreBridge.coreEventsSinceJSON(lastSeenEventID: lastSeenCoreEventID, limit: 64)
        guard let events = decodeCoreEvents(from: payload) else {
            coreEventsJSON = payload
            return
        }

        for event in events {
            lastSeenCoreEventID = max(lastSeenCoreEventID, event.id)
            projectCoreFeedItem(
                kind: "core_event",
                source: event.source,
                itemID: event.id,
                payload: event
            )
        }

        appendCoreEventsToWindow(events)
        coreEventsJSON = encodeCoreEventPayload(events: coreEventWindow) ?? "{\"events\":[]}"
    }

    private func refreshDomainAndToolRuntimeFeeds() {
        let domainPayload = coreBridge.domainEventsSinceJSON(
            lastSeenEventID: lastSeenDomainEventID,
            limit: 64
        )
        if let domainEvents = decodeDomainEvents(from: domainPayload) {
            for domainEvent in domainEvents {
                lastSeenDomainEventID = max(lastSeenDomainEventID, domainEvent.id)
                appendLog(
                    "Domain event consumed: id=\(domainEvent.id), name=\(domainEvent.name), source=\(domainEvent.source)."
                )
                projectCoreFeedItem(
                    kind: "domain_event",
                    source: domainEvent.source,
                    itemID: domainEvent.id,
                    payload: domainEvent
                )
            }
            appendDomainEventsToWindow(domainEvents)
            domainEventsJSON = encodeDomainEventPayload(events: domainEventWindow) ?? "{\"events\":[]}"
        } else {
            domainEventsJSON = domainPayload
        }

        let toolSignalsPayload = coreBridge.toolRuntimeSignalsSinceJSON(
            lastSeenSignalID: lastSeenToolRuntimeSignalID,
            limit: 64
        )
        if let toolSignals = decodeToolRuntimeSignals(from: toolSignalsPayload) {
            for signal in toolSignals {
                lastSeenToolRuntimeSignalID = max(lastSeenToolRuntimeSignalID, signal.id)
                projectCoreFeedItem(
                    kind: "tool_runtime_signal",
                    source: "core.tool_runtime",
                    itemID: signal.id,
                    payload: signal
                )
                consumeToolRuntimeSignal(signal)
            }
            appendToolSignalsToWindow(toolSignals)
            toolRuntimeSignalsJSON = encodeToolSignalPayload(signals: toolSignalWindow) ?? "{\"signals\":[]}"
        } else {
            toolRuntimeSignalsJSON = toolSignalsPayload
        }
    }

    private func refreshCoreSessionHistoryFeed() {
        let payload = coreBridge.coreSessionHistorySinceJSON(
            lastSeenRecordID: lastSeenSessionHistoryRecordID,
            limit: 64
        )
        guard let records = decodeCoreSessionHistory(from: payload) else {
            coreSessionHistoryJSON = payload
            return
        }

        for record in records {
            lastSeenSessionHistoryRecordID = max(lastSeenSessionHistoryRecordID, record.id)
            projectCoreFeedItem(
                kind: "session_history",
                source: "core.session_history",
                itemID: record.id,
                payload: record
            )
        }

        appendSessionHistoryToWindow(records)
        coreSessionHistoryJSON = encodeSessionHistoryPayload(records: sessionHistoryWindow) ?? "{\"records\":[]}"
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
                safetyReason: safetyPayload.reason,
                moveDestinationHint: intentPayload.arguments?.moveDestination,
                moveDestinationKind: intentPayload.arguments?.moveDestinationKind,
                renameTargetHint: intentPayload.arguments?.renameTarget,
                timerDurationHint: intentPayload.arguments?.timerDuration
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
                            safetyReason: invocation.safetyReason,
                            moveDestinationHint: invocation.moveDestinationHint,
                            moveDestinationKindHint: invocation.moveDestinationKind,
                            renameTargetHint: invocation.renameTargetHint,
                            timerDurationHint: invocation.timerDurationHint
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
                        status: executionResult.outcome == .rejected ? "degraded" : "ok",
                        context: [
                            "invocation_id": invocation.id,
                            "origin": invocation.origin,
                            "intent_kind": invocation.intentKind,
                            "safety_decision": invocation.safetyDecision,
                            "outcome": executionResult.outcome.rawValue,
                            "artifact_path": executionResult.artifactPath ?? "",
                            "rejection_code": executionResult.rejectionCode ?? "",
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
                    destructive: $0.destructive,
                    move_destination_hint: $0.moveDestinationHint,
                    move_destination_kind_hint: $0.moveDestinationKind,
                    rename_target_hint: $0.renameTargetHint,
                    timer_duration_hint: $0.timerDurationHint
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

    private func decodeCoreEvents(from payload: String) -> [CoreEventEnvelope]? {
        guard let data = payload.data(using: .utf8) else {
            return nil
        }
        let decoded = try? JSONDecoder().decode(CoreEventsPayload.self, from: data)
        return decoded?.events
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

    private func decodeCoreSessionHistory(from payload: String) -> [CoreSessionHistoryRecordEnvelope]? {
        guard let data = payload.data(using: .utf8) else {
            return nil
        }
        let decoded = try? JSONDecoder().decode(CoreSessionHistoryPayload.self, from: data)
        return decoded?.records
    }

    private func encodeCoreEventPayload(events: [CoreEventEnvelope]) -> String? {
        encodeJSON(CoreEventsPayload(events: events))
    }

    private func encodeDomainEventPayload(events: [DomainEventEnvelope]) -> String? {
        encodeJSON(DomainEventsPayload(events: events))
    }

    private func encodeToolSignalPayload(signals: [ToolRuntimeSignalEnvelope]) -> String? {
        encodeJSON(ToolRuntimeSignalsPayload(signals: signals))
    }

    private func encodeSessionHistoryPayload(records: [CoreSessionHistoryRecordEnvelope]) -> String? {
        encodeJSON(CoreSessionHistoryPayload(records: records))
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(value),
            let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return json
    }

    private func projectCoreFeedItem<T: Encodable>(
        kind: String,
        source: String,
        itemID: UInt64,
        payload: T
    ) {
        guard let payloadJSON = encodeJSON(payload) else {
            return
        }
        coreFeedProjector.append(
            CoreFeedProjectionEvent(
                feedKind: kind,
                source: source,
                itemID: itemID,
                payloadJSON: payloadJSON
            )
        )
    }

    private func appendCoreEventsToWindow(_ events: [CoreEventEnvelope]) {
        guard !events.isEmpty else {
            return
        }
        coreEventWindow.append(contentsOf: events)
        trimWindow(&coreEventWindow, maxCount: 128)
    }

    private func appendDomainEventsToWindow(_ events: [DomainEventEnvelope]) {
        guard !events.isEmpty else {
            return
        }
        domainEventWindow.append(contentsOf: events)
        trimWindow(&domainEventWindow, maxCount: 128)
    }

    private func appendToolSignalsToWindow(_ signals: [ToolRuntimeSignalEnvelope]) {
        guard !signals.isEmpty else {
            return
        }
        toolSignalWindow.append(contentsOf: signals)
        trimWindow(&toolSignalWindow, maxCount: 128)
    }

    private func appendSessionHistoryToWindow(_ records: [CoreSessionHistoryRecordEnvelope]) {
        guard !records.isEmpty else {
            return
        }
        sessionHistoryWindow.append(contentsOf: records)
        trimWindow(&sessionHistoryWindow, maxCount: 256)
    }

    private func trimWindow<T>(_ buffer: inout [T], maxCount: Int) {
        guard buffer.count > maxCount else {
            return
        }
        buffer.removeFirst(buffer.count - maxCount)
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
        let durationMs = currentSessionDurationMs()
        sessionHistoryController.record(
            outcome: outcome,
            transcript: transcript,
            locale: settingsController.locale.rawValue,
            routeProvider: activeRouteProvider,
            durationMs: durationMs,
            errorCode: errorCode,
            injectionDisposition: injectionDisposition
        )

        let coreMirrorStatus = coreBridge.reportCoreSessionHistoryRecord(
            outcome: outcome.rawValue,
            transcript: transcript,
            locale: settingsController.locale.rawValue,
            routeProvider: activeRouteProvider,
            durationMs: durationMs,
            errorCode: errorCode,
            injectionDisposition: injectionDisposition?.rawValue
        )
        if coreMirrorStatus != 0 {
            appendLog("Core session-history mirror failed: status=\(coreMirrorStatus)")
            emitTelemetry(
                category: "session_history",
                action: "core_record_mirror",
                status: "degraded",
                context: ["status": "\(coreMirrorStatus)"]
            )
        } else {
            refreshCoreSessionHistoryFeed()
        }

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

    private func markHotkeySignal(kind: String, message: String) {
        hotkeySignalKind = kind
        hotkeySignalMessage = "\(Self.signalTimestampString()) - \(message)"
    }

    private func updateHotkeyDebug(_ message: String) {
        hotkeyDebugStatus = "\(Self.timestampFormatter.string(from: Date())) \(message)"
    }

    private static func signalTimestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private var ownBundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    private func captureInjectionTargetContext(triggerSource: String) {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return
        }

        let frontmostBundle = frontmostApp.bundleIdentifier
        if frontmostBundle == ownBundleIdentifier {
            emitTelemetry(
                category: "injection_target",
                action: "capture_skipped",
                status: "degraded",
                context: [
                    "trigger_source": triggerSource,
                    "reason": "frontmost_is_syntic",
                ]
            )
            return
        }

        capturedInjectionTargetBundleIdentifier = frontmostBundle
        capturedInjectionTargetProcessIdentifier = frontmostApp.processIdentifier
        emitTelemetry(
            category: "injection_target",
            action: "captured",
            status: "ok",
            context: [
                "trigger_source": triggerSource,
                "bundle": frontmostBundle ?? "unknown",
                "pid": "\(frontmostApp.processIdentifier)",
            ]
        )
    }

    private func clearCapturedInjectionTargetContext() {
        capturedInjectionTargetBundleIdentifier = nil
        capturedInjectionTargetProcessIdentifier = nil
    }

    private func resolvedInjectionTargetContext() -> (bundleIdentifier: String?, processIdentifier: pid_t?) {
        let fallbackBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let bundleIdentifier = capturedInjectionTargetBundleIdentifier ?? fallbackBundle
        let processIdentifier = capturedInjectionTargetProcessIdentifier
        return (bundleIdentifier, processIdentifier)
    }

    private func refocusInjectionTargetIfNeeded(_ targetContext: (bundleIdentifier: String?, processIdentifier: pid_t?)) {
        guard
            let targetBundleIdentifier = targetContext.bundleIdentifier,
            targetBundleIdentifier != ownBundleIdentifier
        else {
            return
        }

        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundleIdentifier {
            return
        }

        if
            let processIdentifier = targetContext.processIdentifier,
            let runningByPID = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == processIdentifier })
        {
            _ = runningByPID.activate(options: NSApplication.ActivationOptions.activateIgnoringOtherApps)
            Thread.sleep(forTimeInterval: 0.12)
            return
        }

        if let runningByBundle = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleIdentifier).first {
            _ = runningByBundle.activate(options: NSApplication.ActivationOptions.activateIgnoringOtherApps)
            Thread.sleep(forTimeInterval: 0.12)
        }
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
    let moveDestinationHint: String?
    let moveDestinationKind: String?
    let renameTargetHint: String?
    let timerDurationHint: String?
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
    let move_destination_hint: String?
    let move_destination_kind_hint: String?
    let rename_target_hint: String?
    let timer_duration_hint: String?
}

private struct CoreEventsPayload: Codable {
    let events: [CoreEventEnvelope]
}

private struct CoreEventEnvelope: Codable {
    let id: UInt64
    let timestampMs: UInt64?
    let kind: String?
    let severity: String?
    let source: String
    let code: String?
    let message: String?
    let permission: String?
    let status: String?
    let detail: String?
    let category: String?
    let action: String?
    let contextJSON: String?
    let valueMs: UInt32?

    enum CodingKeys: String, CodingKey {
        case id
        case timestampMs = "timestamp_ms"
        case kind
        case severity
        case source
        case code
        case message
        case permission
        case status
        case detail
        case category
        case action
        case contextJSON = "context_json"
        case valueMs = "value_ms"
    }
}

private struct DomainEventsPayload: Codable {
    let events: [DomainEventEnvelope]
}

private struct DomainEventEnvelope: Codable {
    let id: UInt64
    let timestampMs: UInt64?
    let name: String
    let source: String
    let phaseBefore: String
    let reviewTranscriptLength: UInt32

    enum CodingKeys: String, CodingKey {
        case id
        case timestampMs = "timestamp_ms"
        case name
        case source
        case phaseBefore = "phase_before"
        case reviewTranscriptLength = "review_transcript_length"
    }
}

private struct ToolRuntimeSignalsPayload: Codable {
    let signals: [ToolRuntimeSignalEnvelope]
}

private struct ToolRuntimeSignalEnvelope: Codable {
    let id: UInt64
    let timestampMs: UInt64?
    let action: String
    let reason: String
    let originDomainEventID: UInt64

    enum CodingKeys: String, CodingKey {
        case id
        case timestampMs = "timestamp_ms"
        case action
        case reason
        case originDomainEventID = "origin_domain_event_id"
    }
}

private struct CoreSessionHistoryPayload: Codable {
    let records: [CoreSessionHistoryRecordEnvelope]
}

private struct CoreSessionHistoryRecordEnvelope: Codable {
    let id: UInt64
    let createdAtMs: UInt64
    let durationMs: UInt32?
    let locale: String
    let routeProvider: String
    let outcome: String
    let transcript: String
    let errorCode: String?
    let injectionDisposition: String?
    let undoneAtMs: UInt64?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAtMs = "created_at_ms"
        case durationMs = "duration_ms"
        case locale
        case routeProvider = "route_provider"
        case outcome
        case transcript
        case errorCode = "error_code"
        case injectionDisposition = "injection_disposition"
        case undoneAtMs = "undone_at_ms"
    }
}

private struct CommandIntentPayload: Decodable {
    let kind: String
    let summary: String
    let confidencePercent: UInt8
    let requiresConfirmation: Bool
    let arguments: CommandIntentArgumentsPayload?

    enum CodingKeys: String, CodingKey {
        case kind
        case summary
        case confidencePercent = "confidence_percent"
        case requiresConfirmation = "requires_confirmation"
        case arguments
    }

    init(
        kind: String,
        summary: String,
        confidencePercent: UInt8,
        requiresConfirmation: Bool,
        arguments: CommandIntentArgumentsPayload?
    ) {
        self.kind = kind
        self.summary = summary
        self.confidencePercent = confidencePercent
        self.requiresConfirmation = requiresConfirmation
        self.arguments = arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "unknown"
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? "Intent parse failed"
        confidencePercent = try container.decodeIfPresent(UInt8.self, forKey: .confidencePercent) ?? 0
        requiresConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
        arguments = try container.decodeIfPresent(CommandIntentArgumentsPayload.self, forKey: .arguments)
    }

    static let unknown = CommandIntentPayload(
        kind: "unknown",
        summary: "Intent parse failed",
        confidencePercent: 0,
        requiresConfirmation: false,
        arguments: nil
    )
}

private struct CommandIntentArgumentsPayload: Decodable {
    let moveDestination: String?
    let moveDestinationKind: String?
    let renameTarget: String?
    let timerDuration: String?

    enum CodingKeys: String, CodingKey {
        case moveDestination = "move_destination"
        case moveDestinationKind = "move_destination_kind"
        case renameTarget = "rename_target"
        case timerDuration = "timer_duration"
    }
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
