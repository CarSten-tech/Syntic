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
    @Published private(set) var dictationStateJSON = "{}"
    @Published private(set) var telemetryLogPath = "-"
    @Published private(set) var logs: [String] = []

    @Published var networkAvailable = true

    private let coreBridge: SynticCoreVersionProviding
    private let settingsController: AppSettingsController
    private let audioAdapter: AudioCapturing
    private let hotkeyAdapter: HotkeyListening
    private let localSttAdapter: STTTranscribing
    private let cloudSttAdapter: STTTranscribing
    private let textInjectionAdapter: TextInjecting
    private let telemetryLogger: StructuredTelemetryLogging

    private var isTranscribing = false

    init(
        coreBridge: SynticCoreVersionProviding,
        settingsController: AppSettingsController,
        audioAdapter: AudioCapturing = MacOSAudioCaptureAdapter(),
        hotkeyAdapter: HotkeyListening = MacOSGlobalHotkeyAdapter(),
        localSttAdapter: STTTranscribing = LocalStubSTTAdapter(),
        cloudSttAdapter: STTTranscribing = CloudStubSTTAdapter(),
        textInjectionAdapter: TextInjecting = MacOSTextInjectionAdapter(),
        telemetryLogger: StructuredTelemetryLogging = NDJSONTelemetryLogger()
    ) {
        self.coreBridge = coreBridge
        self.settingsController = settingsController
        self.audioAdapter = audioAdapter
        self.hotkeyAdapter = hotkeyAdapter
        self.localSttAdapter = localSttAdapter
        self.cloudSttAdapter = cloudSttAdapter
        self.textInjectionAdapter = textInjectionAdapter
        self.telemetryLogger = telemetryLogger

        dictationStateJSON = coreBridge.dictationStateJSON()
        telemetryLogPath = telemetryLogger.logFilePath
        _ = coreBridge.coreEventsClear()
        refreshCoreEventsFeed()
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
        hotkeyAdapter.stopListening()
        _ = audioAdapter.stopCapture()
    }

    var reviewActionsEnabled: Bool {
        phase == "reviewing"
    }

    var recentLogText: String {
        logs.suffix(10).joined(separator: "\n")
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

        _ = coreBridge.dictationReset()
        setPhase("idle", trigger: "cancel_review_completed")
        refreshDictationState()
        emitTelemetry(category: "review", action: "cancelled", status: "ok", context: [:])
        appendLog("Review canceled and state reset.")
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
        _ = coreBridge.dictationFail(reason)
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

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
