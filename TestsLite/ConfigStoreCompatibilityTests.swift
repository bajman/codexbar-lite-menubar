import CodexBarCore
import Foundation
import Testing

@Suite
struct ConfigStoreCompatibilityTests {
    @Test
    func ignoresUnknownProviderIDs() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let fileURL = base.appendingPathComponent("config.json")
        let store = CodexBarConfigStore(fileURL: fileURL)
        let raw = """
        {
          "version": 1,
          "providers": [
            { "id": "codex", "enabled": true, "source": "auto" },
            { "id": "alibaba", "enabled": false },
            { "id": "claude", "enabled": true, "source": "auto" }
          ]
        }
        """
        try raw.write(to: fileURL, atomically: true, encoding: .utf8)

        let config = try #require(try store.load())
        #expect(config.providers.map(\.id) == [.codex, .claude])
        #expect(config.providerConfig(for: .codex)?.enabled == true)
        #expect(config.providerConfig(for: .claude)?.enabled == true)
    }
}
