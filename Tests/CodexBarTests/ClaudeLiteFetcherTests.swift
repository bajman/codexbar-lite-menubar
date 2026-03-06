import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeLiteFetcherTests {
    private func makeCredentialsData(accessToken: String, expiresAt: Date, refreshToken: String? = nil) -> Data {
        let millis = Int(expiresAt.timeIntervalSince1970 * 1000)
        let refreshField: String = {
            guard let refreshToken else { return "" }
            return ",\n            \"refreshToken\": \"\(refreshToken)\""
        }()
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "\(accessToken)",
            "expiresAt": \(millis),
            "scopes": ["user:profile"]\(refreshField)
          }
        }
        """
        return Data(json.utf8)
    }

    @Test
    func expiredCLIManagedCredentialsSurfaceDelegatedRefresh() async throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("credentials.json")
        try self.makeCredentialsData(
            accessToken: "expired-token",
            expiresAt: Date(timeIntervalSinceNow: -3600),
            refreshToken: "refresh-token")
            .write(to: fileURL)

        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
        defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }
        ClaudeOAuthCredentialsStore.invalidateCache()

        await ProviderInteractionContext.$current.withValue(.background) {
            await KeychainCacheStore.withServiceOverrideForTesting(service) {
                await KeychainAccessGate.withTaskOverrideForTesting(true) {
                    KeychainCacheStore.setTestStoreForTesting(true)
                    defer { KeychainCacheStore.setTestStoreForTesting(false) }

                    await ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                        await ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                            await ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                                let fetcher = ClaudeLiteFetcher(environment: [:])

                                do {
                                    _ = try await fetcher.fetchUsage()
                                    Issue.record("Expected delegated refresh error for expired Claude CLI credentials")
                                } catch let error as ClaudeOAuthCredentialsError {
                                    guard case .refreshDelegatedToClaudeCLI = error else {
                                        Issue.record("Expected .refreshDelegatedToClaudeCLI, got \(error)")
                                        return
                                    }
                                } catch {
                                    Issue.record("Expected ClaudeOAuthCredentialsError, got \(error)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
