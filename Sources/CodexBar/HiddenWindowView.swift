import AppKit
import SwiftUI

struct HiddenWindowView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background(HiddenWindowConfigurator())
            .onReceive(NotificationCenter.default.publisher(for: .codexbarOpenSettings)) { _ in
                Task { @MainActor in
                    self.openSettings()
                }
            }
    }
}

private struct HiddenWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { self.configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask = [.borderless]
        window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
        window.isExcludedFromWindowsMenu = true
        window.level = .floating
        window.isOpaque = false
        window.alphaValue = 0
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.setContentSize(NSSize(width: 1, height: 1))
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderOut(nil)
    }
}
