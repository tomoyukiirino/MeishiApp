import Foundation
import os.log

// MARK: - LLMServiceFactory

/// LLMサービスのファクトリー。
/// 設定に基づいて適切なLLMアダプターを生成する。
final class LLMServiceFactory {
    // MARK: - Singleton

    static let shared = LLMServiceFactory()

    private init() {}

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "LLMServiceFactory")

    // MARK: - Public Methods

    /// 現在の設定に基づいてLLMサービスを取得
    /// - Returns: 設定されたLLMサービス、または設定がない場合はnil
    func createService() -> LLMServiceProtocol? {
        let settings = LLMSettingsManager.shared

        // AI構造化が無効の場合
        guard settings.connectionMode != .none else {
            logger.info("LLM connection mode is none")
            return nil
        }

        let provider = settings.selectedProvider
        let apiKey: String?

        switch settings.connectionMode {
        case .none:
            return nil

        case .akkuratSubscription:
            // TODO: Akkuratサブスクリプション経由の場合、サーバーからAPIキーを取得
            // 現在は未実装
            logger.warning("Akkurat subscription mode is not yet implemented")
            return nil

        case .selfApiKey:
            apiKey = KeychainService.shared.getAPIKey(for: provider)
            guard let key = apiKey, !key.isEmpty else {
                logger.warning("No API key found for provider: \(provider.rawValue)")
                return nil
            }
        }

        return createAdapter(for: provider, apiKey: apiKey!)
    }

    /// 指定されたプロバイダー用のアダプターを作成
    /// - Parameters:
    ///   - provider: LLMプロバイダー
    ///   - apiKey: APIキー
    /// - Returns: LLMサービスアダプター
    func createAdapter(for provider: LLMProvider, apiKey: String) -> LLMServiceProtocol {
        logger.info("Creating adapter for provider: \(provider.rawValue)")

        switch provider {
        case .claude:
            return ClaudeAdapter(apiKey: apiKey)
        case .chatgpt:
            return ChatGPTAdapter(apiKey: apiKey)
        case .gemini:
            return GeminiAdapter(apiKey: apiKey)
        case .perplexity:
            return PerplexityAdapter(apiKey: apiKey)
        }
    }

    /// 現在のサービスが利用可能か確認
    var isServiceAvailable: Bool {
        let settings = LLMSettingsManager.shared

        switch settings.connectionMode {
        case .none:
            return false
        case .akkuratSubscription:
            // TODO: サブスクリプション状態を確認
            return false
        case .selfApiKey:
            let provider = settings.selectedProvider
            return KeychainService.shared.hasAPIKey(for: provider)
        }
    }

    /// 指定プロバイダーで画像入力が利用可能か
    func supportsImageInput(for provider: LLMProvider) -> Bool {
        provider.supportsImageInput
    }
}
