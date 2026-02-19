import SwiftUI

struct SettingsView: View {
    let coreBridge: SynticCoreVersionProviding

    var body: some View {
        Form {
            Section("Runtime") {
                LabeledContent("Core-Version") {
                    Text(coreBridge.coreVersion())
                }

                LabeledContent("FFI-Status") {
                    Text(coreBridge.isFFILinked ? "linked" : "not linked")
                }
            }

            Section("Nächster Schritt") {
                Text("Vor Swift-Build zuerst `./scripts/build-ffi.sh` ausführen und anschließend Spike Lab testen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 480)
    }
}
