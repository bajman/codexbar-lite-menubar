import Foundation

#if os(macOS)
import LocalAuthentication
import Security

enum KeychainNoUIQuery {
    static func apply(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        // NOTE: The non-UI policy is controlled via LAContext.interactionNotAllowed. Use the authentication
        // context rather than the deprecated kSecUseAuthenticationUI flags.
    }
}
#endif
