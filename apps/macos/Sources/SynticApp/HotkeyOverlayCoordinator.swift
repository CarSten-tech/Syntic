import AppKit
import Combine
import SwiftUI

@MainActor
final class HotkeyOverlayCoordinator {
    private var signalKindCancellable: AnyCancellable?
    private var audioLevelCancellable: AnyCancellable?
    private let overlayWindowController = HotkeyOverlayWindowController()

    init(pipeline: TechnicalE2EPipeline) {
        signalKindCancellable = pipeline.$hotkeySignalKind
            .dropFirst()
            .sink { [weak self] kind in
                self?.handleHotkeySignal(kind: kind)
            }

        audioLevelCancellable = pipeline.$latestAudioLevel
            .sink { [weak self] level in
                self?.overlayWindowController.updateAudioLevel(level)
            }
    }

    private func handleHotkeySignal(kind: String) {
        switch kind {
        case "start":
            overlayWindowController.show()
        case "stop", "ignored", "idle":
            overlayWindowController.hide()
        default:
            break
        }
    }
}

@MainActor
private final class HotkeyOverlayWindowController {
    private var panel: NSPanel?
    private let waveformModel = HotkeyOverlayWaveformModel()

    func show() {
        ensurePanel()
        repositionPanel()
        guard let panel else {
            return
        }
        if panel.isVisible {
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func ensurePanel() {
        if panel != nil {
            return
        }

        let initialFrame = NSRect(x: 200, y: 200, width: 186, height: 42)
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

        let host = NSHostingView(rootView: HotkeyOverlayPillView(model: waveformModel))
        host.frame = NSRect(origin: .zero, size: initialFrame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel
    }

    private func repositionPanel() {
        guard let panel, let screen = preferredScreen else {
            return
        }

        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let topPadding: CGFloat = 38 // approx. 1cm under menu bar
        let width = min(186, screen.visibleFrame.width - 40)
        let height: CGFloat = 42
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

    func updateAudioLevel(_ level: Float) {
        waveformModel.level = CGFloat(max(0, min(1, level)))
    }
}

@MainActor
private final class HotkeyOverlayWaveformModel: ObservableObject {
    @Published var level: CGFloat = 0
}

private struct HotkeyOverlayPillView: View {
    @ObservedObject var model: HotkeyOverlayWaveformModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(Color.black.opacity(0.92))
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)

            ZStack {
                LiveWaveformView(level: model.level)
                    .frame(width: 80, height: 16)

                HStack {
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.trailing, 12)
            }
            .padding(.horizontal, 12)
        }
    }
}

private struct LiveWaveformView: View {
    let level: CGFloat
    private let barCount = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(opacity(for: index)))
                        .frame(width: 3, height: height(for: index, time: t, level: level))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func height(for index: Int, time: TimeInterval, level: CGFloat) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let distanceFromCenter = abs(Double(index) - center)
        let centerWeight = max(0.2, 1 - (distanceFromCenter / center))
        let wave = (sin((time * 6.6) + (Double(index) * 0.78)) + 1) / 2
        let normalizedLevel = max(0.05, min(1, level))
        let activity = Double(normalizedLevel) * (0.4 + (0.6 * wave))
        let amplitude = activity * centerWeight
        return CGFloat(3 + (14 * amplitude))
    }

    private func opacity(for index: Int) -> Double {
        let center = Double(barCount - 1) / 2
        let distanceFromCenter = abs(Double(index) - center)
        let centerWeight = max(0.35, 1 - (distanceFromCenter / center))
        return 0.38 + (0.62 * centerWeight)
    }
}
