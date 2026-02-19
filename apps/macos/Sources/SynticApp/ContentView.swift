import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow

    let coreBridge: SynticCoreVersionProviding
    @State private var dictationText = "Syntic test transcript"
    @State private var lastDictationStatusCode: UInt8 = 0
    @State private var dictationStatePayload = ""
    @State private var commandUtterance = "Stelle einen Timer auf 20min"
    @State private var commandIntentPayload = ""
    @State private var commandSafetyPayload = ""

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

            Button("Spike Lab öffnen") {
                openWindow(id: "spike-lab")
            }

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 430)
        .onAppear {
            refreshDictationStatePayload()
            refreshCommandPayloads()
        }
    }

    private func refreshDictationStatePayload() {
        dictationStatePayload = coreBridge.dictationStateJSON()
    }

    private func refreshCommandPayloads() {
        commandIntentPayload = coreBridge.commandClassifyJSON(commandUtterance)
        commandSafetyPayload = coreBridge.commandSafetyJSON(commandUtterance)
    }
}
