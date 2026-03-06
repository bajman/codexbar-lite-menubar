import CodexBarCore
import Foundation

enum MenuBarDisplayText {
    static func percentText(window: RateWindow?, showUsed: Bool) -> String? {
        guard let window else { return nil }
        let percent = showUsed ? window.usedPercent : window.remainingPercent
        let clamped = min(100, max(0, percent))
        return String(format: "%.0f%%", clamped)
    }

    static func paceText(provider: UsageProvider, window: RateWindow?, now: Date = .init()) -> String? {
        guard let window else { return nil }
        guard provider == .codex || provider == .claude else { return nil }
        guard window.remainingPercent > 0 else { return nil }
        guard let pace = UsagePace.weekly(window: window, now: now, defaultWindowMinutes: 10080) else { return nil }
        let deltaValue = Int(abs(pace.deltaPercent).rounded())
        let sign = pace.deltaPercent >= 0 ? "+" : "-"
        return "\(sign)\(deltaValue)%"
    }

    static func displayText(
        mode: MenuBarDisplayMode,
        provider: UsageProvider,
        percentWindow: RateWindow?,
        paceWindow: RateWindow?,
        showUsed: Bool,
        now: Date = .init()) -> String?
    {
        switch mode {
        case .percent:
            return self.percentText(window: percentWindow, showUsed: showUsed)
        case .pace:
            return self.paceText(provider: provider, window: paceWindow, now: now)
        case .both:
            let percent = self.percentText(window: percentWindow, showUsed: showUsed)
            let pace = Self.paceText(provider: provider, window: paceWindow, now: now)
            switch (percent, pace) {
            case let (.some(percent), .some(pace)):
                return "\(percent) · \(pace)"
            case let (.some(percent), nil):
                return percent
            case let (nil, .some(pace)):
                return pace
            case (nil, nil):
                return nil
            }
        }
    }
}
