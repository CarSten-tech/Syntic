import SwiftUI

@main
struct SynticApp: App {
    private let coreBridge = SynticCoreBridge()
    @StateObject private var settingsController = AppSettingsController()
    @StateObject private var sessionHistoryController = SessionHistoryController()

    var body: some Scene {
        MenuBarExtra("Syntic", systemImage: "waveform") {
            ContentView(
                coreBridge: coreBridge,
                settingsController: settingsController,
                sessionHistoryController: sessionHistoryController
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                coreBridge: coreBridge,
                settingsController: settingsController,
                sessionHistoryController: sessionHistoryController
            )
        }

        Window("Spike Lab", id: "spike-lab") {
            SpikeLabView()
        }
        .windowResizability(.contentSize)
    }
}
