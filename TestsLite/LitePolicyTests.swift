import CodexBarCore
import Testing

@Suite
struct LitePolicyTests {
    @Test
    func onlyOAuthKindIsAllowed() {
        #expect(LitePolicy.allowedKinds == [.oauth])
        #expect(!LitePolicy.allowedKinds.contains(.cli))
        #expect(!LitePolicy.allowedKinds.contains(.web))
        #expect(!LitePolicy.allowedKinds.contains(.webDashboard))
    }

    @Test
    func codexUnauthorizedMessageGuidesRelogin() {
        let message = CodexOAuthFetchError.unauthorized.errorDescription ?? ""
        #expect(message.contains("codex login"))
        #expect(message.lowercased().contains("expired") || message.lowercased().contains("invalid"))
    }

    @Test
    func claudeUnauthorizedMessageGuidesRelogin() {
        let message = ClaudeOAuthFetchError.unauthorized.errorDescription ?? ""
        #expect(message.contains("claude login"))
        #expect(message.lowercased().contains("expired") || message.lowercased().contains("invalid"))
    }

    @Test
    func strategyResolutionForcesOAuthOnly() {
        let codexFromCLI = CodexProviderDescriptor.resolveUsageStrategy(selectedDataSource: .cli, hasOAuthCredentials: true)
        let codexFromAuto = CodexProviderDescriptor.resolveUsageStrategy(selectedDataSource: .auto, hasOAuthCredentials: false)
        #expect(codexFromCLI.dataSource == .oauth)
        #expect(codexFromAuto.dataSource == .oauth)

        let claudeFromWeb = ClaudeProviderDescriptor.resolveUsageStrategy(
            selectedDataSource: .web,
            webExtrasEnabled: true,
            hasWebSession: true,
            hasCLI: true,
            hasOAuthCredentials: false)
        let claudeFromCLI = ClaudeProviderDescriptor.resolveUsageStrategy(
            selectedDataSource: .cli,
            webExtrasEnabled: false,
            hasWebSession: false,
            hasCLI: true,
            hasOAuthCredentials: true)
        #expect(claudeFromWeb.dataSource == .oauth)
        #expect(!claudeFromWeb.useWebExtras)
        #expect(claudeFromCLI.dataSource == .oauth)
    }
}
