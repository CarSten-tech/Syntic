import AppKit
import ApplicationServices
import Carbon.HIToolbox
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
    func startListening(onTrigger: @escaping (String) -> Void) -> HotkeyListenerStartResult
    func stopListening()
}

final class MacOSGlobalHotkeyAdapter: HotkeyListening {
    private static let signature: OSType = 0x5359_4E54 // "SYNT"

    private let hotkeys: [HotkeyDefinition]

    private var eventHandlerRef: EventHandlerRef?
    private var registeredHotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var hotkeyLabelsByID: [UInt32: String] = [:]
    private var trigger: ((String) -> Void)?
    private var hasPromptedAccessibilityPermission = false

    init(hotkeys: [HotkeyDefinition] = [.optionSpace, .optionDelete]) {
        self.hotkeys = hotkeys
    }

    var isListening: Bool {
        !registeredHotkeyRefs.isEmpty
    }

    var supportedHotkeysDescription: String {
        hotkeys.map(\.label).joined(separator: " / ")
    }

    func startListening(onTrigger: @escaping (String) -> Void) -> HotkeyListenerStartResult {
        stopListening()

        let permissionResult = promptAccessibilityPermissionIfNeeded()
        trigger = onTrigger
        let installStatus = installHotkeyEventHandlerIfNeeded()
        if installStatus == noErr {
            registerConfiguredHotkeys()
        }

        let hasGlobalMonitor = !registeredHotkeyRefs.isEmpty
        let hasLocalMonitor = false
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
        for hotkeyRef in registeredHotkeyRefs.values {
            UnregisterEventHotKey(hotkeyRef)
        }
        registeredHotkeyRefs.removeAll()
        hotkeyLabelsByID.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        trigger = nil
    }

    private func installHotkeyEventHandlerIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else {
            return noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else {
                return OSStatus(eventNotHandledErr)
            }
            let adapter = Unmanaged<MacOSGlobalHotkeyAdapter>.fromOpaque(userData).takeUnretainedValue()
            return adapter.handleHotkeyEvent(event)
        }

        return InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
    }

    private func registerConfiguredHotkeys() {
        for (index, hotkey) in hotkeys.enumerated() {
            let hotkeyID = UInt32(index + 1)
            let eventHotkeyID = EventHotKeyID(signature: Self.signature, id: hotkeyID)
            var hotkeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(hotkey.keyCode),
                carbonModifiers(from: hotkey.modifiers),
                eventHotkeyID,
                GetApplicationEventTarget(),
                0,
                &hotkeyRef
            )

            guard status == noErr, let hotkeyRef else {
                continue
            }

            registeredHotkeyRefs[hotkeyID] = hotkeyRef
            hotkeyLabelsByID[hotkeyID] = hotkey.label
        }
    }

    private func handleHotkeyEvent(_ event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard status == noErr else {
            return status
        }
        guard let hotkeyLabel = hotkeyLabelsByID[hotkeyID.id] else {
            return noErr
        }

        trigger?(hotkeyLabel)
        return noErr
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
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
