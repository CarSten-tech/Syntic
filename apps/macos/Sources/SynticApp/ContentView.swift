import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow

    let coreBridge: SynticCoreVersionProviding
    @ObservedObject var settingsController: AppSettingsController
    @StateObject private var technicalE2EPipeline: TechnicalE2EPipeline
    private let finderContextAdapter = MacOSFinderContextAdapter()

    @State private var dictationText = "Syntic test transcript"
    @State private var lastDictationStatusCode: UInt8 = 0
    @State private var dictationStatePayload = ""
    @State private var commandUtterance = "Stelle einen Timer auf 20min"
    @State private var commandIntentPayload = ""
    @State private var commandSafetyPayload = ""
    @State private var finderSnapshotSummary = "-"

    init(coreBridge: SynticCoreVersionProviding, settingsController: AppSettingsController) {
        self.coreBridge = coreBridge
        self.settingsController = settingsController
        _technicalE2EPipeline = StateObject(
            wrappedValue: TechnicalE2EPipeline(coreBridge: coreBridge, settingsController: settingsController)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Syntic")
                .font(.headline)

            Text("Bootstrap erfolgreich erstellt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Text("Core-Version: \(coreBridge.coreVersion())")
                .font(.caption)

            Text("Health: \(coreBridge.healthSnapshotJSON())")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Divider()

            Text("Dictation Core Flow (technisch)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Transkript", text: $dictationText)

            HStack {
                Button("Reset") {
                    lastDictationStatusCode = coreBridge.dictationReset()
                    refreshDictationStatePayload()
                }
                Button("Start") {
                    lastDictationStatusCode = coreBridge.dictationStart()
                    refreshDictationStatePayload()
                }
                Button("Partial") {
                    lastDictationStatusCode = coreBridge.dictationAppendPartial(dictationText)
                    refreshDictationStatePayload()
                }
            }

            HStack {
                Button("Finalize") {
                    lastDictationStatusCode = coreBridge.dictationFinalizeReview(dictationText)
                    refreshDictationStatePayload()
                }
                Button("Confirm") {
                    lastDictationStatusCode = coreBridge.dictationConfirm()
                    refreshDictationStatePayload()
                }
                Button("Cancel") {
                    lastDictationStatusCode = coreBridge.dictationCancel()
                    refreshDictationStatePayload()
                }
            }

            Text("Last status code: \(lastDictationStatusCode)")
                .font(.caption2)

            Text("Dictation state: \(dictationStatePayload)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            Divider()

            Text("Command Core Flow (technisch)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Command-Eingabe", text: $commandUtterance)

            HStack {
                Button("Classify") {
                    refreshCommandPayloads()
                }
                Button("Fail Dictation") {
                    lastDictationStatusCode = coreBridge.dictationFail("manual test failure")
                    refreshDictationStatePayload()
                }
            }

            Text("Intent: \(commandIntentPayload)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            Text("Safety: \(commandSafetyPayload)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            Divider()

            Text("Technical E2E: Hotkey -> Audio -> Routing -> Review -> Injection")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Toggle("Network verfügbar", isOn: $technicalE2EPipeline.networkAvailable)
                Toggle("Sensitive Mode", isOn: $settingsController.sensitiveModeEnabled)
            }

            Picker("Locale", selection: $settingsController.locale) {
                ForEach(DictationLocale.allCases) { locale in
                    Text(locale.displayName).tag(locale)
                }
            }

            Picker("Routing Mode", selection: $settingsController.routingMode) {
                ForEach(STTRoutingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Text("Settings: \(settingsController.persistenceSummary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Button(technicalE2EPipeline.isHotkeyListening ? "Hotkey Listener stoppen" : "Hotkey Listener starten") {
                    technicalE2EPipeline.toggleHotkeyListener()
                }
                Button("Manual Trigger") {
                    technicalE2EPipeline.triggerHotkeyAction()
                }
            }

            HStack {
                Button("Review Confirm") {
                    technicalE2EPipeline.confirmReview()
                }
                .disabled(!technicalE2EPipeline.reviewActionsEnabled)

                Button("Review Cancel") {
                    technicalE2EPipeline.cancelReview()
                }
                .disabled(!technicalE2EPipeline.reviewActionsEnabled)

                Button("Finder Snapshot") {
                    refreshFinderSnapshotSummary()
                }
            }

            Text("E2E phase: \(technicalE2EPipeline.phase)")
                .font(.caption2)
            Text("Audio level: \(String(format: "%.2f", technicalE2EPipeline.latestAudioLevel))")
                .font(.caption2)
            Text("Route: \(technicalE2EPipeline.latestRouteJSON)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text("Transcript: \(technicalE2EPipeline.latestTranscript)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("Injection: \(technicalE2EPipeline.latestInjectionSummary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("Core dictation state: \(technicalE2EPipeline.dictationStateJSON)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text("Core events: \(technicalE2EPipeline.coreEventsJSON)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            Text("Telemetry log: \(technicalE2EPipeline.telemetryLogPath)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("Finder snapshot: \(finderSnapshotSummary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            ScrollView {
                Text(technicalE2EPipeline.recentLogText)
                    .font(.caption2.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 96)

            Divider()

            Button("Spike Lab öffnen") {
                openWindow(id: "spike-lab")
            }

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 640)
        .onAppear {
            refreshDictationStatePayload()
            refreshCommandPayloads()
            refreshFinderSnapshotSummary()
        }
    }

    private func refreshDictationStatePayload() {
        dictationStatePayload = coreBridge.dictationStateJSON()
    }

    private func refreshCommandPayloads() {
        commandIntentPayload = coreBridge.commandClassifyJSON(commandUtterance)
        commandSafetyPayload = coreBridge.commandSafetyJSON(commandUtterance)
    }

    private func refreshFinderSnapshotSummary() {
        let snapshot = finderContextAdapter.currentSelectionSnapshot()
        finderSnapshotSummary =
            "status=\(snapshot.status.rawValue), running=\(snapshot.finderRunning), frontmost=\(snapshot.finderFrontmost), selected=\(snapshot.selectedPaths.count)"
    }
}
