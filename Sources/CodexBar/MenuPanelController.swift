import AppKit
import CodexBarCore
import SwiftUI

@MainActor
final class MenuPanelController {
    private var panel: MenuPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var glassView: NSGlassEffectView?
    private nonisolated(unsafe) var globalClickMonitor: Any?
    private nonisolated(unsafe) var localClickMonitor: Any?
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
        let hosting = self.hostingView(for: content)
        let fittingSize = hosting.fittingSize

        let panelRect = NSRect(origin: .zero, size: fittingSize)
        let panel: MenuPanel
        if let existing = self.panel {
            existing.setContentSize(fittingSize)
            panel = existing
        } else {
            panel = MenuPanel(contentRect: panelRect)
            self.panel = panel
        }

        let contentView = self.wrapInGlassIfNeeded(hosting)
        if panel.contentView !== contentView {
            panel.contentView = contentView
        }

        let origin = self.panelOrigin(relativeTo: button, panelSize: fittingSize)
        panel.setFrameOrigin(origin)

        self.isShowing = true
        self.installMonitors()

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func dismiss(animated: Bool = true) {
        guard self.isShowing else { return }
        self.isShowing = false
        self.removeMonitors()

        guard let panel = self.panel else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                    self.teardownContent()
                }
            }
        } else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            self.teardownContent()
        }
    }

    func updateContent() {
        guard self.isShowing, let panel = self.panel else { return }
        let content = self.contentBuilder()
        let hosting = self.hostingView(for: content)
        let contentView = self.wrapInGlassIfNeeded(hosting)
        if panel.contentView !== contentView {
            panel.contentView = contentView
        }

        let fittingSize = hosting.fittingSize
        var frame = panel.frame
        frame.size = fittingSize
        // Keep top-left anchored
        let oldTop = frame.origin.y + panel.frame.size.height
        frame.origin.y = oldTop - fittingSize.height
        panel.setFrame(frame, display: true)
    }

    // MARK: - Glass Wrapping

    private func hostingView(for content: AnyView) -> NSHostingView<AnyView> {
        if let hosting = self.hostingView {
            hosting.rootView = content
            return hosting
        }

        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.intrinsicContentSize]
        self.hostingView = hosting
        return hosting
    }

    private func wrapInGlassIfNeeded(_ hosting: NSHostingView<AnyView>) -> NSView {
        if #available(macOS 26, *), LiquidGlassAvailability.shouldApplyGlass {
            if let glass = self.glassView {
                glass.contentView = hosting
                return glass
            }

            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = MenuPanelMetrics.shellCornerRadius
            glass.contentView = hosting
            self.glassView = glass
            return glass
        }
        self.glassView = nil
        return hosting
    }

    private func teardownContent() {
        self.panel?.contentView = nil
        self.hostingView = nil
        self.glassView = nil
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
        let panelY = buttonFrameOnScreen.minY - panelSize.height - MenuPanelMetrics.panelAttachmentGap

        // Ensure panel doesn't clip off-screen
        guard let screen = buttonWindow.screen ?? NSScreen.main else {
            return NSPoint(x: panelX, y: panelY)
        }

        let visibleFrame = screen.visibleFrame
        var origin = NSPoint(x: panelX, y: panelY)

        // Clamp horizontal
        if origin.x + panelSize.width > visibleFrame.maxX {
            origin.x = visibleFrame.maxX - panelSize.width - MenuPanelMetrics.screenEdgeInset
        }
        if origin.x < visibleFrame.minX {
            origin.x = visibleFrame.minX + MenuPanelMetrics.screenEdgeInset
        }

        // Clamp vertical
        if origin.y < visibleFrame.minY {
            origin.y = visibleFrame.minY + MenuPanelMetrics.screenEdgeInset
        }

        return origin
    }

    // MARK: - Event Monitors

    private func installMonitors() {
        // Clicks delivered to OTHER applications.
        self.globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown])
        { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isShowing else { return }
                self.dismiss()
            }
        }

        // Clicks delivered to THIS application but outside the panel.
        self.localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown])
        { [weak self] event in
            guard let self, self.isShowing else { return event }
            // If the click is inside the panel, let it through normally.
            if let panel = self.panel, event.window === panel {
                return event
            }
            // Click is in our app but outside the panel (e.g. status bar
            // icon for toggle) — dismiss synchronously so isShowing is
            // already false when statusItemClicked fires immediately after.
            self.dismiss()
            return event
        }

        self.localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                DispatchQueue.main.async {
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
        if let monitor = self.localClickMonitor {
            NSEvent.removeMonitor(monitor)
            self.localClickMonitor = nil
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
        if let monitor = self.localClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = self.localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
