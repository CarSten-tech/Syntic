import SwiftUI

@MainActor
@main
struct SynticApp: App {
    private let coreBridge: SynticCoreBridge
    @StateObject private var settingsController: AppSettingsController
    @StateObject private var sessionHistoryController: SessionHistoryController
    @StateObject private var technicalE2EPipeline: TechnicalE2EPipeline
    private let hotkeyOverlayCoordinator: HotkeyOverlayCoordinator

    init() {
        let coreBridge = SynticCoreBridge()
        let settingsController = AppSettingsController()
        let sessionHistoryController = SessionHistoryController()
        let technicalE2EPipeline = TechnicalE2EPipeline(
            coreBridge: coreBridge,
            settingsController: settingsController,
            sessionHistoryController: sessionHistoryController
        )

        self.coreBridge = coreBridge
        _settingsController = StateObject(wrappedValue: settingsController)
        _sessionHistoryController = StateObject(wrappedValue: sessionHistoryController)
        _technicalE2EPipeline = StateObject(wrappedValue: technicalE2EPipeline)
        hotkeyOverlayCoordinator = HotkeyOverlayCoordinator(pipeline: technicalE2EPipeline)
    }

    var body: some Scene {
        let _ = hotkeyOverlayCoordinator

        MenuBarExtra("Syntic", systemImage: "waveform") {
            ContentView(
                coreBridge: coreBridge,
                settingsController: settingsController,
                sessionHistoryController: sessionHistoryController,
                technicalE2EPipeline: technicalE2EPipeline
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
