import Foundation
import Security
import os.log

// MARK: - KeychainService

/// APIキーを安全に保存するためのKeychainサービス
final class KeychainService {
    // MARK: - Singleton

    static let shared = KeychainService()

    private init() {}

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "KeychainService")
    private let serviceName = "jp.akkurat.MeishiApp.LLMAPIKeys"

    // MARK: - Public Methods

    /// APIキーを保存
    /// - Parameters:
    ///   - apiKey: 保存するAPIキー
    ///   - provider: LLMプロバイダー
    func saveAPIKey(_ apiKey: String, for provider: LLMProvider) {
        let account = provider.rawValue

        // 既存のキーを削除
        deleteAPIKey(for: provider)

        guard let data = apiKey.data(using: .utf8) else {
            logger.error("Failed to encode API key")
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            logger.info("API key saved for provider: \(provider.rawValue)")
        } else {
            logger.error("Failed to save API key: \(status)")
        }
    }

    /// APIキーを取得
    /// - Parameter provider: LLMプロバイダー
    /// - Returns: 保存されているAPIキー、または nil
    func getAPIKey(for provider: LLMProvider) -> String? {
        let account = provider.rawValue

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let apiKey = String(data: data, encoding: .utf8) {
            return apiKey
        }

        if status != errSecItemNotFound {
            logger.error("Failed to get API key: \(status)")
        }

        return nil
    }

    /// APIキーを削除
    /// - Parameter provider: LLMプロバイダー
    func deleteAPIKey(for provider: LLMProvider) {
        let account = provider.rawValue

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess {
            logger.info("API key deleted for provider: \(provider.rawValue)")
        } else if status != errSecItemNotFound {
            logger.error("Failed to delete API key: \(status)")
        }
    }

    /// APIキーが存在するか確認
    /// - Parameter provider: LLMプロバイダー
    /// - Returns: APIキーが存在する場合は true
    func hasAPIKey(for provider: LLMProvider) -> Bool {
        getAPIKey(for: provider) != nil
    }

    /// すべてのプロバイダーのAPIキーを削除
    func deleteAllAPIKeys() {
        for provider in LLMProvider.allCases {
            deleteAPIKey(for: provider)
        }
        logger.info("All API keys deleted")
    }

    /// APIキーのマスク表示用文字列を取得
    /// - Parameter provider: LLMプロバイダー
    /// - Returns: マスクされたAPIキー（例: "sk-ant-...xxxx"）
    func getMaskedAPIKey(for provider: LLMProvider) -> String? {
        guard let apiKey = getAPIKey(for: provider), !apiKey.isEmpty else {
            return nil
        }

        // 最初の7文字 + "..." + 最後の4文字
        if apiKey.count > 15 {
            let prefix = String(apiKey.prefix(7))
            let suffix = String(apiKey.suffix(4))
            return "\(prefix)...\(suffix)"
        } else if apiKey.count > 4 {
            let suffix = String(apiKey.suffix(4))
            return "....\(suffix)"
        } else {
            return "****"
        }
    }
}
