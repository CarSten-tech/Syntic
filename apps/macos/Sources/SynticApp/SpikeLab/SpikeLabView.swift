import AppKit
import SwiftUI

struct SpikeLabView: View {
    private let probe = TextInjectionProbe()

    @State private var probeText = "Syntic Spike DE: äöü ß 123"
    @State private var delaySeconds = 3
    @State private var activeAppName = ""
    @State private var logLines: [String] = []
    @State private var lastResult: TextInjectionProbeResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spike 01: Text Injection Kompatibilität")
                .font(.headline)

            Text("Fokus auf Ziel-App setzen, dann Methode mit Delay ausführen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox("Input") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Testtext", text: $probeText)
                    HStack {
                        Stepper("Delay: \(delaySeconds)s", value: $delaySeconds, in: 0 ... 10)
                        Spacer()
                        Button("Accessibility öffnen") {
                            probe.openAccessibilitySettings()
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Ausführen") {
                HStack {
                    Button("AX Inject starten") {
                        run(method: .accessibility)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("CGEvent Inject starten") {
                        run(method: .cgEvent)
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
                .padding(8)
            }

            GroupBox("Matrix-Helfer") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("App-Name (z. B. TextEdit)", text: $activeAppName)

                    Button("Letzte Zeile in Clipboard kopieren") {
                        copyLastMatrixLineToClipboard()
                    }
                    .disabled(lastResult == nil || activeAppName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(8)
            }

            GroupBox("Log") {
                ScrollView {
                    Text(logLines.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
                .padding(8)
            }
        }
        .padding()
        .frame(width: 700, height: 560)
        .onAppear {
            appendLog("Accessibility trusted: \(probe.accessibilityPermissionGranted())")
        }
    }

    private func run(method: TextInjectionMethod) {
        let trimmedText = probeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            appendLog("Eingabe leer. Bitte Testtext eintragen.")
            return
        }

        appendLog("Methode \(method.rawValue) startet in \(delaySeconds)s. Jetzt Ziel-App fokussieren.")

        let delay = DispatchTimeInterval.seconds(delaySeconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let result: TextInjectionProbeResult
            switch method {
            case .accessibility:
                result = probe.injectWithAccessibility(text: trimmedText)
            case .cgEvent:
                result = probe.injectWithCGEvent(text: trimmedText)
            }

            DispatchQueue.main.async {
                lastResult = result
                appendLog(format(result: result))
            }
        }
    }

    private func appendLog(_ line: String) {
        logLines.append("\(timestampString(date: Date())) \(line)")
    }

    private func format(result: TextInjectionProbeResult) -> String {
        let status = result.success ? "SUCCESS" : "FAIL"
        return "[\(status)] \(result.method.rawValue) \(result.detail)"
    }

    private func copyLastMatrixLineToClipboard() {
        guard let result = lastResult else {
            return
        }

        let trimmedAppName = activeAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAppName.isEmpty else {
            return
        }

        let axValue = result.method == .accessibility ? (result.success ? "OK" : "FAIL") : "TBD"
        let cgEventValue = result.method == .cgEvent ? (result.success ? "OK" : "FAIL") : "TBD"
        let preferredMethod = result.success ? result.method.rawValue : "Clipboard"
        let notes = result.detail.replacingOccurrences(of: "|", with: "/")
        let markdownRow = "| \(trimmedAppName) | \(axValue) | \(cgEventValue) | TBD | \(preferredMethod) | \(notes) |"

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdownRow, forType: .string)

        appendLog("Matrix-Zeile ins Clipboard kopiert.")
    }

    private func timestampString(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
