import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow

    let coreBridge: SynticCoreVersionProviding

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

            Button("Spike Lab öffnen") {
                openWindow(id: "spike-lab")
            }

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 340)
    }
}
