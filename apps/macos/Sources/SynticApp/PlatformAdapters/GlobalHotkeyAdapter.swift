import AppKit
import ApplicationServices
import Foundation

struct HotkeyDefinition {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    static let optionSpace = HotkeyDefinition(keyCode: 49, modifiers: [.option])
}

protocol HotkeyListening: AnyObject {
    var isListening: Bool { get }
    func startListening(onTrigger: @escaping () -> Void)
    func stopListening()
}

final class MacOSGlobalHotkeyAdapter: HotkeyListening {
    private let hotkey: HotkeyDefinition

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var trigger: (() -> Void)?
    private var hasPromptedAccessibilityPermission = false

    init(hotkey: HotkeyDefinition = .optionSpace) {
        self.hotkey = hotkey
    }

    var isListening: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    func startListening(onTrigger: @escaping () -> Void) {
        stopListening()

        promptAccessibilityPermissionIfNeeded()
        trigger = onTrigger

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
            return event
        }
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
        guard matches(event: event) else {
            return
        }

        trigger?()
    }

    private func matches(event: NSEvent) -> Bool {
        guard event.keyCode == hotkey.keyCode else {
            return false
        }

        let relevantModifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        return relevantModifiers == hotkey.modifiers
    }

    private func promptAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else {
            return
        }
        guard !hasPromptedAccessibilityPermission else {
            return
        }

        hasPromptedAccessibilityPermission = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
