import CodexBarCore
import Testing

@Suite
struct LitePolicyLinuxTests {
    @Test
    func unauthorizedErrorsContainLoginGuidance() {
        let codex = CodexOAuthFetchError.unauthorized.errorDescription ?? ""
        let claude = ClaudeOAuthFetchError.unauthorized.errorDescription ?? ""
        #expect(codex.contains("codex login"))
        #expect(claude.contains("claude login"))
    }
}
