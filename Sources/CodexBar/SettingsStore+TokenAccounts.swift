import AppKit
import CodexBarCore
import Foundation

extension SettingsStore {
    func tokenAccountsData(for _: UsageProvider) -> ProviderTokenAccountData? {
        nil
    }

    func tokenAccounts(for _: UsageProvider) -> [ProviderTokenAccount] {
        []
    }

    func selectedTokenAccount(for _: UsageProvider) -> ProviderTokenAccount? {
        nil
    }

    func setActiveTokenAccountIndex(_: Int, for _: UsageProvider) {}

    func addTokenAccount(provider _: UsageProvider, label _: String, token _: String) {}

    func removeTokenAccount(provider _: UsageProvider, accountID _: UUID) {}

    func ensureTokenAccountsLoaded() {
        self.tokenAccountsLoaded = true
    }

    func reloadTokenAccounts() {
        self.tokenAccountsLoaded = true
        self.updateProviderTokenAccounts([:])
    }

    func openTokenAccountsFile() {
        do {
            try self.configStore.save(self.config)
            NSWorkspace.shared.open(self.configStore.fileURL)
        } catch {
            CodexBarLog.logger(LogCategories.tokenAccounts).error("Failed to persist config: \(error)")
        }
    }
}
