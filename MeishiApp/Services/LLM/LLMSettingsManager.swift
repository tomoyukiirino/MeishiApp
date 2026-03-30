import Foundation
import Combine
import os.log

// MARK: - LLMSettingsManager

/// LLM設定の管理クラス
final class LLMSettingsManager: ObservableObject {
    // MARK: - Singleton

    static let shared = LLMSettingsManager()

    private init() {
        loadSettings()
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "LLMSettingsManager")

    // UserDefaultsキー
    private enum Keys {
        static let connectionMode = "llm.connectionMode"
        static let selectedProvider = "llm.selectedProvider"
        static let privacyMode = "llm.privacyMode"
        static let hasShownDisclosure = "llm.hasShownDisclosure"
    }

    // MARK: - Published Properties

    /// 接続モード
    @Published var connectionMode: LLMConnectionMode = .none {
        didSet {
            saveConnectionMode()
        }
    }

    /// 選択中のLLMプロバイダー
    @Published var selectedProvider: LLMProvider = .claude {
        didSet {
            saveSelectedProvider()
        }
    }

    /// プライバシーモード
    @Published var privacyMode: LLMPrivacyMode = .privacyFirst {
        didSet {
            savePrivacyMode()
        }
    }

    /// AI構造化の説明を表示済みか
    @Published var hasShownDisclosure: Bool = false {
        didSet {
            UserDefaults.standard.set(hasShownDisclosure, forKey: Keys.hasShownDisclosure)
        }
    }

    // MARK: - Computed Properties

    /// AI構造化が有効か
    var isAIStructuringEnabled: Bool {
        connectionMode != .none && LLMServiceFactory.shared.isServiceAvailable
    }

    /// 現在のプロバイダーが画像入力をサポートするか
    var currentProviderSupportsImage: Bool {
        selectedProvider.supportsImageInput
    }

    /// 精度優先モードが利用可能か（プロバイダーが画像をサポートしている場合のみ）
    var accuracyModeAvailable: Bool {
        currentProviderSupportsImage
    }

    // MARK: - Private Methods

    private func loadSettings() {
        // 接続モード
        if let rawValue = UserDefaults.standard.string(forKey: Keys.connectionMode),
           let mode = LLMConnectionMode(rawValue: rawValue) {
            connectionMode = mode
        }

        // プロバイダー
        if let rawValue = UserDefaults.standard.string(forKey: Keys.selectedProvider),
           let provider = LLMProvider(rawValue: rawValue) {
            selectedProvider = provider
        }

        // プライバシーモード
        if let rawValue = UserDefaults.standard.string(forKey: Keys.privacyMode),
           let mode = LLMPrivacyMode(rawValue: rawValue) {
            privacyMode = mode
        }

        // 説明表示済みフラグ
        hasShownDisclosure = UserDefaults.standard.bool(forKey: Keys.hasShownDisclosure)

        logger.info("Settings loaded - mode: \(self.connectionMode.rawValue), provider: \(self.selectedProvider.rawValue)")
    }

    private func saveConnectionMode() {
        UserDefaults.standard.set(connectionMode.rawValue, forKey: Keys.connectionMode)
        logger.info("Connection mode saved: \(self.connectionMode.rawValue)")
    }

    private func saveSelectedProvider() {
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: Keys.selectedProvider)
        logger.info("Provider saved: \(self.selectedProvider.rawValue)")

        // プロバイダーが画像をサポートしない場合、プライバシー優先モードに強制変更
        if !selectedProvider.supportsImageInput && privacyMode == .accuracyFirst {
            privacyMode = .privacyFirst
            logger.info("Privacy mode forced to privacyFirst due to provider limitation")
        }
    }

    private func savePrivacyMode() {
        UserDefaults.standard.set(privacyMode.rawValue, forKey: Keys.privacyMode)
        logger.info("Privacy mode saved: \(self.privacyMode.rawValue)")
    }

    // MARK: - Public Methods

    /// 設定をリセット
    func resetSettings() {
        connectionMode = .none
        selectedProvider = .claude
        privacyMode = .privacyFirst
        hasShownDisclosure = false
        KeychainService.shared.deleteAllAPIKeys()
        logger.info("All LLM settings reset")
    }

    /// プロバイダーのAPIキーが設定されているか確認
    func hasAPIKey(for provider: LLMProvider) -> Bool {
        KeychainService.shared.hasAPIKey(for: provider)
    }

    /// 現在のプロバイダーのAPIキーが設定されているか確認
    var hasCurrentProviderAPIKey: Bool {
        hasAPIKey(for: selectedProvider)
    }
}

// MARK: - Migration from ClaudeAPIService

extension LLMSettingsManager {
    /// 旧ClaudeAPIServiceの設定を移行
    func migrateFromLegacySettings() {
        // 旧APIキーをUserDefaultsから取得
        if let legacyAPIKey = UserDefaults.standard.string(forKey: "claudeAPIKey"),
           !legacyAPIKey.isEmpty {
            // Keychainに移行
            KeychainService.shared.saveAPIKey(legacyAPIKey, for: .claude)
            // 旧設定を削除
            UserDefaults.standard.removeObject(forKey: "claudeAPIKey")
            logger.info("Migrated legacy Claude API key to Keychain")
        }

        // 旧構造化モードを移行
        if let legacyMode = UserDefaults.standard.string(forKey: "aiStructuringMode") {
            if let mode = LLMPrivacyMode(rawValue: legacyMode) {
                privacyMode = mode
            }
            // 旧設定を削除
            UserDefaults.standard.removeObject(forKey: "aiStructuringMode")
            logger.info("Migrated legacy structuring mode")
        }

        // 旧説明表示フラグを移行
        if UserDefaults.standard.object(forKey: "hasShownAIDisclosure") != nil {
            hasShownDisclosure = UserDefaults.standard.bool(forKey: "hasShownAIDisclosure")
            UserDefaults.standard.removeObject(forKey: "hasShownAIDisclosure")
            logger.info("Migrated legacy disclosure flag")
        }

        // Claudeの設定があれば、自動的にselfApiKeyモードに設定
        if KeychainService.shared.hasAPIKey(for: .claude) && connectionMode == .none {
            connectionMode = .selfApiKey
            selectedProvider = .claude
            logger.info("Auto-configured to selfApiKey mode with Claude")
        }
    }
}
