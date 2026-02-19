import AppKit
import Foundation

struct TextInjectionProbeResult {
    let method: TextInjectionMethod
    let success: Bool
    let detail: String
    let timestamp: Date
}

struct TextInjectionProbe {
    private let adapter = MacOSTextInjectionAdapter()

    func accessibilityPermissionGranted() -> Bool {
        adapter.accessibilityPermissionGranted()
    }

    func openAccessibilitySettings() {
        adapter.openAccessibilitySettings()
    }

    func injectWithAccessibility(text: String) -> TextInjectionProbeResult {
        let result = adapter.inject(
            text: text,
            strategy: .accessibilityFirst,
            preferClipboardFor: nil
        )

        return TextInjectionProbeResult(
            method: result.method,
            success: result.disposition == .injected,
            detail: result.detail,
            timestamp: Date()
        )
    }

    func injectWithCGEvent(text: String) -> TextInjectionProbeResult {
        let result = adapter.inject(
            text: text,
            strategy: .cgEventFirst,
            preferClipboardFor: nil
        )

        return TextInjectionProbeResult(
            method: result.method,
            success: result.disposition == .injected,
            detail: result.detail,
            timestamp: Date()
        )
    }
}
