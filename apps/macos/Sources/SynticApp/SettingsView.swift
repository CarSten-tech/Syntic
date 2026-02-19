import SwiftUI

struct SettingsView: View {
    let coreBridge: SynticCoreVersionProviding
    @ObservedObject var settingsController: AppSettingsController

    var body: some View {
        Form {
            Section("Dictation") {
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

                Toggle("Sensitive Mode", isOn: $settingsController.sensitiveModeEnabled)
            }

            Section("Persistenz") {
                LabeledContent("Datei") {
                    Text(settingsController.settingsFilePath)
                        .font(.caption2)
                        .lineLimit(2)
                }

                LabeledContent("Status") {
                    Text(settingsController.persistenceSummary)
                        .font(.caption)
                        .lineLimit(2)
                }

                HStack {
                    Button("Neu laden") {
                        settingsController.reloadFromDisk()
                    }

                    Button("Defaults wiederherstellen") {
                        settingsController.resetToDefaults()
                    }
                }
            }

            Section("Runtime") {
                LabeledContent("Core-Version") {
                    Text(coreBridge.coreVersion())
                }

                LabeledContent("FFI-Status") {
                    Text(coreBridge.isFFILinked ? "linked" : "not linked")
                }
            }

            Section("Nächster Schritt") {
                Text("Settings werden direkt in Application Support gespeichert und beim Start geladen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 480)
    }
}
