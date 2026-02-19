import AppKit
import ApplicationServices
import Foundation

struct HotkeyDefinition {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let label: String

    static let optionSpace = HotkeyDefinition(keyCode: 49, modifiers: [.option], label: "Option+Space")
    static let optionDelete = HotkeyDefinition(keyCode: 51, modifiers: [.option], label: "Option+Backspace")

    func matches(event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else {
            return false
        }

        let relevantModifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        return relevantModifiers == modifiers
    }
}

struct HotkeyListenerStartResult {
    let started: Bool
    let hasGlobalMonitor: Bool
    let hasLocalMonitor: Bool
    let accessibilityTrusted: Bool
    let promptedAccessibility: Bool
    let hotkeyLabels: [String]

    var hotkeySummary: String {
        hotkeyLabels.joined(separator: " / ")
    }

    var statusSummary: String {
        let accessibility = accessibilityTrusted ? "granted" : "missing"
        return "hotkeys=\(hotkeySummary), global=\(hasGlobalMonitor ? "on" : "off"), local=\(hasLocalMonitor ? "on" : "off"), accessibility=\(accessibility)"
    }
}

protocol HotkeyListening: AnyObject {
    var isListening: Bool { get }
    var supportedHotkeysDescription: String { get }
    func startListening(onTrigger: @escaping () -> Void) -> HotkeyListenerStartResult
    func stopListening()
}

final class MacOSGlobalHotkeyAdapter: HotkeyListening {
    private let hotkeys: [HotkeyDefinition]

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var trigger: (() -> Void)?
    private var hasPromptedAccessibilityPermission = false

    init(hotkeys: [HotkeyDefinition] = [.optionSpace, .optionDelete]) {
        self.hotkeys = hotkeys
    }

    var isListening: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    var supportedHotkeysDescription: String {
        hotkeys.map(\.label).joined(separator: " / ")
    }

    func startListening(onTrigger: @escaping () -> Void) -> HotkeyListenerStartResult {
        stopListening()

        let permissionResult = promptAccessibilityPermissionIfNeeded()
        trigger = onTrigger

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
            return event
        }

        let hasGlobalMonitor = globalMonitor != nil
        let hasLocalMonitor = localMonitor != nil
        return HotkeyListenerStartResult(
            started: hasGlobalMonitor || hasLocalMonitor,
            hasGlobalMonitor: hasGlobalMonitor,
            hasLocalMonitor: hasLocalMonitor,
            accessibilityTrusted: permissionResult.accessibilityTrusted,
            promptedAccessibility: permissionResult.promptedAccessibility,
            hotkeyLabels: hotkeys.map(\.label)
        )
    }

    func stopListening() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        trigger = nil
    }

    private func handle(event: NSEvent) {
        guard !event.isARepeat else {
            return
        }

        guard matches(event: event) else {
            return
        }

        trigger?()
    }

    private func matches(event: NSEvent) -> Bool {
        hotkeys.contains { hotkey in
            hotkey.matches(event: event)
        }
    }

    private func promptAccessibilityPermissionIfNeeded() -> (accessibilityTrusted: Bool, promptedAccessibility: Bool) {
        if AXIsProcessTrusted() {
            return (true, false)
        }

        if hasPromptedAccessibilityPermission {
            return (AXIsProcessTrusted(), false)
        }

        hasPromptedAccessibilityPermission = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return (AXIsProcessTrusted(), true)
    }
}
