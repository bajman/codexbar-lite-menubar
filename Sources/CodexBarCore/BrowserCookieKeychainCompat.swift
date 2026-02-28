import Foundation

public struct BrowserCookieKeychainPromptContext: Sendable {
    public let label: String

    public init(label: String) {
        self.label = label
    }
}

public enum BrowserCookieKeychainPromptHandler {
    public nonisolated(unsafe) static var handler: (@Sendable (BrowserCookieKeychainPromptContext) -> Void)?
}

public enum BrowserCookieKeychainAccessGate {
    public nonisolated(unsafe) static var isDisabled: Bool = false
}
