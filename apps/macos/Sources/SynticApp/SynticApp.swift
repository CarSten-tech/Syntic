import SwiftUI

@main
struct SynticApp: App {
    private let coreBridge = SynticCoreBridge()

    var body: some Scene {
        MenuBarExtra("Syntic", systemImage: "waveform") {
            ContentView(coreBridge: coreBridge)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(coreBridge: coreBridge)
        }
    }
}
