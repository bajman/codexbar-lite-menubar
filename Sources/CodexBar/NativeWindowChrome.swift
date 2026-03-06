import AppKit
import SwiftUI

enum NativeWindowChromeStyle {
    case settings
    case standardDocument

    var hidesTitle: Bool {
        self == .settings
    }

    var toolbarStyle: NSWindow.ToolbarStyle? {
        guard #available(macOS 11, *) else { return nil }
        return switch self {
        case .settings: .preference
        case .standardDocument: nil
        }
    }
}

@MainActor
enum NativeWindowChromeNormalizer {
    private static let fallbackTrafficLightSpacing: CGFloat = 6

    static func apply(to window: NSWindow, style: NativeWindowChromeStyle) {
        if let toolbarStyle = style.toolbarStyle {
            window.toolbarStyle = toolbarStyle
        }
        window.titlebarAppearsTransparent = false
        window.titleVisibility = style.hidesTitle ? .hidden : .visible
        self.alignTrafficLights(in: window)
    }

    private static func alignTrafficLights(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let container = close.superview,
              mini.superview === container,
              zoom.superview === container
        else {
            return
        }

        container.layoutSubtreeIfNeeded()
        close.isHidden = false
        mini.isHidden = false
        zoom.isHidden = false

        let spacing = self.normalizedSpacing(close: close, mini: mini, zoom: zoom)
        let targetY = round((container.bounds.height - close.frame.height) / 2)
        let closeOriginX = close.frame.minX

        close.setFrameOrigin(NSPoint(x: closeOriginX, y: targetY))
        mini.setFrameOrigin(NSPoint(x: close.frame.maxX + spacing, y: targetY))
        zoom.setFrameOrigin(NSPoint(x: mini.frame.maxX + spacing, y: targetY))
    }

    private static func normalizedSpacing(close: NSButton, mini: NSButton, zoom: NSButton) -> CGFloat {
        let candidates = [
            mini.frame.minX - close.frame.maxX,
            zoom.frame.minX - mini.frame.maxX,
        ].filter { $0 > 0 }

        guard !candidates.isEmpty else { return self.fallbackTrafficLightSpacing }
        let average = candidates.reduce(0, +) / CGFloat(candidates.count)
        return max(4, min(8, average))
    }
}

struct NativeWindowChromeAccessor: NSViewRepresentable {
    let style: NativeWindowChromeStyle

    func makeCoordinator() -> Coordinator {
        Coordinator(style: self.style)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor in
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            context.coordinator.attach(to: nsView.window)
        }
    }

    final class Coordinator {
        private let style: NativeWindowChromeStyle
        private var observers: [NSObjectProtocol] = []
        private weak var window: NSWindow?

        init(style: NativeWindowChromeStyle) {
            self.style = style
        }

        deinit {
            self.removeObservers()
        }

        @MainActor
        func attach(to window: NSWindow?) {
            guard let window else { return }

            if self.window !== window {
                self.removeObservers()
                self.window = window
                self.installObservers(for: window)
            }

            NativeWindowChromeNormalizer.apply(to: window, style: self.style)
        }

        private func installObservers(for window: NSWindow) {
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didResizeNotification,
            ]
            let style = self.style

            self.observers = names.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { notification in
                    guard let observedWindow = notification.object as? NSWindow else { return }
                    Task { @MainActor in
                        NativeWindowChromeNormalizer.apply(to: observedWindow, style: style)
                    }
                }
            }
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            self.observers.forEach(center.removeObserver)
            self.observers.removeAll()
        }
    }
}
