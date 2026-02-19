import AppKit
import Combine
import SwiftUI

@MainActor
final class HotkeyOverlayCoordinator {
    private var signalCancellable: AnyCancellable?
    private let overlayWindowController = HotkeyOverlayWindowController()

    init(pipeline: TechnicalE2EPipeline) {
        signalCancellable = pipeline.$hotkeySignalMessage
            .combineLatest(pipeline.$hotkeySignalKind)
            .dropFirst()
            .sink { [weak self] message, kind in
                self?.handleHotkeySignal(message: message, kind: kind)
            }
    }

    private func handleHotkeySignal(message: String, kind: String) {
        if kind == "idle" {
            overlayWindowController.hide()
            return
        }
        overlayWindowController.show(message: message, kind: kind)
    }
}

@MainActor
private final class HotkeyOverlayWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<HotkeyOverlayBannerView>?
    private var autoHideTask: Task<Void, Never>?

    func show(message: String, kind: String) {
        ensurePanel()
        hostingView?.rootView = HotkeyOverlayBannerView(message: message, kind: kind)
        repositionPanel()
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
        scheduleAutoHide()
    }

    func hide() {
        autoHideTask?.cancel()
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        if panel != nil {
            return
        }

        let initialFrame = NSRect(x: 200, y: 200, width: 540, height: 54)
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: HotkeyOverlayBannerView(message: "-", kind: "idle"))
        host.frame = NSRect(origin: .zero, size: initialFrame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.hostingView = host
        self.panel = panel
    }

    private func repositionPanel() {
        guard let panel, let screen = preferredScreen else {
            return
        }

        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let topPadding: CGFloat = 38 // approx. 1cm under menu bar
        let width = min(540, screen.visibleFrame.width - 40)
        let height: CGFloat = 54
        let originX = screen.frame.midX - (width / 2)
        let originY = screen.frame.maxY - menuBarHeight - topPadding - height

        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
    }

    private var preferredScreen: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screenAtMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screenAtMouse
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else {
                return
            }
            self.panel?.orderOut(nil)
        }
    }
}

private struct HotkeyOverlayBannerView: View {
    let message: String
    let kind: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accentColor)
                .frame(width: 10, height: 10)
            Text(message)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }

    private var accentColor: Color {
        switch kind {
        case "start":
            return .green
        case "stop":
            return .orange
        case "ignored":
            return .red
        default:
            return .gray
        }
    }
}
