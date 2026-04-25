import AppKit

@MainActor
final class MenuPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        self.level = .statusBar
        self.isMovable = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.animationBehavior = .utilityWindow
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        // Prevent the panel from taking the app out of its current activation
        // state; the global-click + escape monitors handle dismissal instead of
        // relying on resignKey which fires spuriously for non-activating panels.
        self.becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    // Dismissal is handled by the event monitors in MenuPanelController
    // rather than resignKey, which fires spuriously for non-activating panels.
}
