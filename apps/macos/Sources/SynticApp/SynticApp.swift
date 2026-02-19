import SwiftUI

@main
struct SynticApp: App {
    private let coreBridge = SynticCoreBridge()
    @StateObject private var settingsController = AppSettingsController()

    var body: some Scene {
        MenuBarExtra("Syntic", systemImage: "waveform") {
            ContentView(coreBridge: coreBridge, settingsController: settingsController)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(coreBridge: coreBridge, settingsController: settingsController)
        }

        Window("Spike Lab", id: "spike-lab") {
            SpikeLabView()
        }
        .windowResizability(.contentSize)
    }
}
