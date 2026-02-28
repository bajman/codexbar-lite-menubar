import AppKit
import SwiftUI

@MainActor
final class MenuPanelController {
    private var panel: MenuPanel?
    private var hostingView: NSHostingView<AnyView>?
    private nonisolated(unsafe) var globalClickMonitor: Any?
    private nonisolated(unsafe) var localKeyMonitor: Any?
    private(set) var isShowing = false
    private let contentBuilder: () -> AnyView

    init(@ViewBuilder content: @escaping () -> some View) {
        self.contentBuilder = { AnyView(content()) }
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if self.isShowing {
            self.dismiss()
        } else {
            self.show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard !self.isShowing else { return }

        let content = self.contentBuilder()
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.intrinsicContentSize]
        let fittingSize = hosting.fittingSize

        let panelRect = NSRect(origin: .zero, size: fittingSize)
        let panel: MenuPanel
        if let existing = self.panel {
            existing.setContentSize(fittingSize)
            panel = existing
        } else {
            panel = MenuPanel(contentRect: panelRect)
            panel.onResignKey = { [weak self] in
                self?.dismiss()
            }
            self.panel = panel
        }

        panel.contentView = hosting
        self.hostingView = hosting

        let origin = self.panelOrigin(relativeTo: button, panelSize: fittingSize)
        panel.setFrameOrigin(origin)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.isShowing = true
        self.installMonitors()
    }

    func dismiss() {
        guard self.isShowing else { return }
        self.isShowing = false
        self.removeMonitors()

        guard let panel = self.panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        }
    }

    func updateContent() {
        guard self.isShowing, let panel = self.panel else { return }
        let content = self.contentBuilder()
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        self.hostingView = hosting

        let fittingSize = hosting.fittingSize
        var frame = panel.frame
        frame.size = fittingSize
        // Keep top-left anchored
        let oldTop = frame.origin.y + panel.frame.size.height
        frame.origin.y = oldTop - fittingSize.height
        panel.setFrame(frame, display: true)
    }

    // MARK: - Positioning

    private func panelOrigin(relativeTo button: NSStatusBarButton, panelSize: NSSize) -> NSPoint {
        guard let buttonWindow = button.window else {
            return NSPoint(x: 100, y: 100)
        }

        let buttonBounds = button.bounds
        let buttonFrameInWindow = button.convert(buttonBounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

        // Center panel horizontally under the button
        let panelX = buttonFrameOnScreen.midX - panelSize.width / 2
        // Position panel below the menu bar
        let panelY = buttonFrameOnScreen.minY - panelSize.height - 4

        // Ensure panel doesn't clip off-screen
        guard let screen = buttonWindow.screen ?? NSScreen.main else {
            return NSPoint(x: panelX, y: panelY)
        }

        let visibleFrame = screen.visibleFrame
        var origin = NSPoint(x: panelX, y: panelY)

        // Clamp horizontal
        if origin.x + panelSize.width > visibleFrame.maxX {
            origin.x = visibleFrame.maxX - panelSize.width - 4
        }
        if origin.x < visibleFrame.minX {
            origin.x = visibleFrame.minX + 4
        }

        // Clamp vertical
        if origin.y < visibleFrame.minY {
            origin.y = visibleFrame.minY + 4
        }

        return origin
    }

    // MARK: - Event Monitors

    private func installMonitors() {
        self.globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown])
        { [weak self] event in
            Task { @MainActor in
                guard let self, self.isShowing else { return }
                if let panel = self.panel, let eventWindow = event.window, eventWindow == panel {
                    return
                }
                self.dismiss()
            }
        }

        self.localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                Task { @MainActor in
                    self.dismiss()
                }
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = self.globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            self.globalClickMonitor = nil
        }
        if let monitor = self.localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            self.localKeyMonitor = nil
        }
    }

    deinit {
        if let monitor = self.globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = self.localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
