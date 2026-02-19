import AppKit
import ApplicationServices
import Foundation

enum TextInjectionMethod: String, CaseIterable {
    case accessibility = "AX"
    case cgEvent = "CGEvent"
    case clipboard = "Clipboard"
}

enum TextInjectionDisposition {
    case injected
    case clipboardFallback
    case failed
}

struct TextInjectionResult {
    let disposition: TextInjectionDisposition
    let method: TextInjectionMethod
    let detail: String
}

enum TextInjectionStrategy {
    case accessibilityFirst
    case cgEventFirst
}

protocol TextInjecting {
    func inject(
        text: String,
        strategy: TextInjectionStrategy,
        preferClipboardFor bundleIdentifier: String?
    ) -> TextInjectionResult
}

struct MacOSTextInjectionAdapter: TextInjecting {
    private let clipboardPreferredBundleIdentifiers: Set<String> = [
        "com.figma.Desktop",
        "com.1password.1password"
    ]
    private let forceClipboardFallback: Bool
    private let autoPasteAfterClipboardFallback: Bool

    init(
        forceClipboardFallback: Bool = ProcessInfo.processInfo.environment["SYNTIC_FORCE_CLIPBOARD_FALLBACK"] == "1",
        autoPasteAfterClipboardFallback: Bool = ProcessInfo.processInfo.environment["SYNTIC_DISABLE_CLIPBOARD_AUTOPASTE"] != "1"
    ) {
        self.forceClipboardFallback = forceClipboardFallback
        self.autoPasteAfterClipboardFallback = autoPasteAfterClipboardFallback
    }

    func inject(
        text: String,
        strategy: TextInjectionStrategy = .accessibilityFirst,
        preferClipboardFor bundleIdentifier: String? = nil
    ) -> TextInjectionResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return TextInjectionResult(
                disposition: .failed,
                method: .accessibility,
                detail: "Kein Text zum Injizieren vorhanden."
            )
        }

        if forceClipboardFallback {
            return putTextOnClipboard(trimmedText, detail: "Clipboard-Fallback via SYNTIC_FORCE_CLIPBOARD_FALLBACK=1 erzwungen.")
        }

        if shouldForceClipboard(bundleIdentifier: bundleIdentifier) {
            return putTextOnClipboard(trimmedText, detail: "Bundle-ID in Clipboard-Override-Liste.")
        }

        switch strategy {
        case .accessibilityFirst:
            let axAttempt = injectUsingAccessibility(trimmedText)
            if axAttempt.disposition == .injected {
                return axAttempt
            }

            let cgAttempt = injectUsingCGEvent(trimmedText)
            if cgAttempt.disposition == .injected {
                return cgAttempt
            }

            return putTextOnClipboard(
                trimmedText,
                detail: "AX und CGEvent fehlgeschlagen: \(axAttempt.detail) | \(cgAttempt.detail)"
            )

        case .cgEventFirst:
            let cgAttempt = injectUsingCGEvent(trimmedText)
            if cgAttempt.disposition == .injected {
                return cgAttempt
            }

            let axAttempt = injectUsingAccessibility(trimmedText)
            if axAttempt.disposition == .injected {
                return axAttempt
            }

            return putTextOnClipboard(
                trimmedText,
                detail: "CGEvent und AX fehlgeschlagen: \(cgAttempt.detail) | \(axAttempt.detail)"
            )
        }
    }

    func accessibilityPermissionGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        guard
            let settingsURL = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }

    private func shouldForceClipboard(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else {
            return false
        }

        return clipboardPreferredBundleIdentifiers.contains(bundleIdentifier)
    }

    private func injectUsingAccessibility(_ text: String) -> TextInjectionResult {
        guard accessibilityPermissionGranted() else {
            return TextInjectionResult(
                disposition: .failed,
                method: .accessibility,
                detail: "Accessibility-Berechtigung fehlt."
            )
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?

        let focusedElementError = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard focusedElementError == .success, let rawFocusedElement = focusedElementRef else {
            return TextInjectionResult(
                disposition: .failed,
                method: .accessibility,
                detail: "Kein fokussiertes UI-Element (\(describe(axError: focusedElementError)))."
            )
        }

        guard CFGetTypeID(rawFocusedElement) == AXUIElementGetTypeID() else {
            return TextInjectionResult(
                disposition: .failed,
                method: .accessibility,
                detail: "Fokussiertes Element ist kein AXUIElement."
            )
        }

        let focusedElement = unsafeBitCast(rawFocusedElement, to: AXUIElement.self)
        let setValueError = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )

        if setValueError == .success {
            return TextInjectionResult(
                disposition: .injected,
                method: .accessibility,
                detail: "Text in fokussiertes AX-Element geschrieben."
            )
        }

        return TextInjectionResult(
            disposition: .failed,
            method: .accessibility,
            detail: "Setzen von kAXValueAttribute fehlgeschlagen (\(describe(axError: setValueError)))."
        )
    }

    private func injectUsingCGEvent(_ text: String) -> TextInjectionResult {
        guard accessibilityPermissionGranted() else {
            return TextInjectionResult(
                disposition: .failed,
                method: .cgEvent,
                detail: "Accessibility-Berechtigung fehlt (CGEvent blockiert)."
            )
        }

        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            return TextInjectionResult(
                disposition: .failed,
                method: .cgEvent,
                detail: "CGEventSource konnte nicht erstellt werden."
            )
        }

        for utf16Unit in text.utf16 {
            var unicodeChar = [utf16Unit]

            guard
                let keyDownEvent = CGEvent(
                    keyboardEventSource: eventSource,
                    virtualKey: 0,
                    keyDown: true
                ),
                let keyUpEvent = CGEvent(
                    keyboardEventSource: eventSource,
                    virtualKey: 0,
                    keyDown: false
                )
            else {
                return TextInjectionResult(
                    disposition: .failed,
                    method: .cgEvent,
                    detail: "Erzeugen von Keyboard-Events fehlgeschlagen."
                )
            }

            keyDownEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
            keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
            keyDownEvent.post(tap: .cghidEventTap)
            keyUpEvent.post(tap: .cghidEventTap)
        }

        return TextInjectionResult(
            disposition: .injected,
            method: .cgEvent,
            detail: "Unicode-Keyevents gesendet."
        )
    }

    private func putTextOnClipboard(_ text: String, detail: String) -> TextInjectionResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if autoPasteAfterClipboardFallback {
            let pasteResult = postPasteShortcut()
            if pasteResult.sent {
                return TextInjectionResult(
                    disposition: .clipboardFallback,
                    method: .clipboard,
                    detail: "\(detail) Text auf Clipboard gelegt. Cmd+V gesendet (\(pasteResult.detail))."
                )
            }

            return TextInjectionResult(
                disposition: .clipboardFallback,
                method: .clipboard,
                detail: "\(detail) Text auf Clipboard gelegt. Cmd+V fehlgeschlagen (\(pasteResult.detail))."
            )
        }

        return TextInjectionResult(
            disposition: .clipboardFallback,
            method: .clipboard,
            detail: "\(detail) Text auf Clipboard gelegt."
        )
    }

    private func postPasteShortcut() -> (sent: Bool, detail: String) {
        guard accessibilityPermissionGranted() else {
            return (false, "Accessibility-Berechtigung fehlt")
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return (false, "CGEventSource fehlgeschlagen")
        }

        let keyCodeForV: CGKeyCode = 9
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: false)
        else {
            return (false, "Cmd+V Events konnten nicht erstellt werden")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return (true, "posted")
    }

    private func describe(axError: AXError) -> String {
        switch axError {
        case .success:
            return "success"
        case .failure:
            return "failure"
        case .illegalArgument:
            return "illegalArgument"
        case .invalidUIElement:
            return "invalidUIElement"
        case .invalidUIElementObserver:
            return "invalidUIElementObserver"
        case .cannotComplete:
            return "cannotComplete"
        case .attributeUnsupported:
            return "attributeUnsupported"
        case .actionUnsupported:
            return "actionUnsupported"
        case .notificationUnsupported:
            return "notificationUnsupported"
        case .notImplemented:
            return "notImplemented"
        case .notificationAlreadyRegistered:
            return "notificationAlreadyRegistered"
        case .notificationNotRegistered:
            return "notificationNotRegistered"
        case .apiDisabled:
            return "apiDisabled"
        case .noValue:
            return "noValue"
        case .parameterizedAttributeUnsupported:
            return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision:
            return "notEnoughPrecision"
        @unknown default:
            return "unknown(\(axError.rawValue))"
        }
    }
}
