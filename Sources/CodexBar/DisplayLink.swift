import AppKit
import Observation
import QuartzCore

/// Minimal display link driver using macOS 15+ display links, with a timer fallback on older systems.
/// Publishes ticks on the main thread at the requested frame rate.
@MainActor
@Observable
final class DisplayLinkDriver {
    // Published counter used to drive SwiftUI updates.
    var tick: Int = 0
    private var displayLink: CADisplayLink?
    private var timer: Timer?
    private var targetInterval: CFTimeInterval = 1.0 / 60.0
    private var lastTickTimestamp: CFTimeInterval = 0
    private let onTick: (() -> Void)?

    init(onTick: (() -> Void)? = nil) {
        self.onTick = onTick
    }

    func start(fps: Double = 12) {
        guard self.displayLink == nil, self.timer == nil else { return }
        let clampedFps = max(fps, 1)
        self.targetInterval = 1.0 / clampedFps
        self.lastTickTimestamp = 0
        if #available(macOS 15, *), let screen = NSScreen.main {
            let displayLink = screen.displayLink(target: self, selector: #selector(self.step(_:)))
            let rate = Float(clampedFps)
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: rate,
                maximum: rate,
                preferred: rate)
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        } else {
            self.startTimer()
        }
    }

    func stop() {
        self.displayLink?.invalidate()
        self.displayLink = nil
        self.timer?.invalidate()
        self.timer = nil
    }

    @objc private func step(_: CADisplayLink) {
        self.handleTick()
    }

    private func handleTick() {
        let now = CACurrentMediaTime()
        if self.lastTickTimestamp > 0, now - self.lastTickTimestamp < self.targetInterval {
            return
        }
        self.lastTickTimestamp = now
        // Safe on main runloop; drives SwiftUI updates.
        self.tick &+= 1
        self.onTick?()
    }

    private func startTimer() {
        guard self.timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: self.targetInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTick()
            }
        }
        timer.tolerance = self.targetInterval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }
}
