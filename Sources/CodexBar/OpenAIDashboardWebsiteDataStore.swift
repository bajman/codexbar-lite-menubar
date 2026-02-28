import Foundation
import WebKit

enum OpenAIDashboardWebsiteDataStore {
    @MainActor
    static func store(forAccountEmail _: String?) -> WKWebsiteDataStore {
        .default()
    }
}
