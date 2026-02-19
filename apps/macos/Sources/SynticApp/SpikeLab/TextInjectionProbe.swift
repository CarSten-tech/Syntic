import AppKit
import ApplicationServices
import Foundation

enum TextInjectionMethod: String, CaseIterable {
    case accessibility = "AX"
    case cgEvent = "CGEvent"
}

struct TextInjectionProbeResult {
    let method: TextInjectionMethod
    let success: Bool
    let detail: String
    let timestamp: Date
}

struct TextInjectionProbe {
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

    func injectWithAccessibility(text: String) -> TextInjectionProbeResult {
        guard accessibilityPermissionGranted() else {
            return result(
                method: .accessibility,
                success: false,
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
            return result(
                method: .accessibility,
                success: false,
                detail: "Kein fokussiertes UI-Element gefunden (\(describe(axError: focusedElementError)))."
            )
        }

        guard CFGetTypeID(rawFocusedElement) == AXUIElementGetTypeID() else {
            return result(
                method: .accessibility,
                success: false,
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
            return result(method: .accessibility, success: true, detail: "Text gesetzt.")
        }

        return result(
            method: .accessibility,
            success: false,
            detail: "Setzen von kAXValueAttribute fehlgeschlagen (\(describe(axError: setValueError)))."
        )
    }

    func injectWithCGEvent(text: String) -> TextInjectionProbeResult {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            return result(
                method: .cgEvent,
                success: false,
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
                return result(
                    method: .cgEvent,
                    success: false,
                    detail: "Erzeugen von Keyboard-Events fehlgeschlagen."
                )
            }

            keyDownEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
            keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
            keyDownEvent.post(tap: .cghidEventTap)
            keyUpEvent.post(tap: .cghidEventTap)
        }

        return result(method: .cgEvent, success: true, detail: "Unicode-Keyevents gesendet.")
    }

    private func result(
        method: TextInjectionMethod,
        success: Bool,
        detail: String
    ) -> TextInjectionProbeResult {
        TextInjectionProbeResult(
            method: method,
            success: success,
            detail: detail,
            timestamp: Date()
        )
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
