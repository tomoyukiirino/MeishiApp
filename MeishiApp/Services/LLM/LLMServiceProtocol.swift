import Foundation
import UIKit

// MARK: - LLMServiceProtocol

/// LLM（大規模言語モデル）サービスの共通インターフェース。
/// 名刺のOCRテキストまたは画像から構造化データを抽出する機能を提供。
protocol LLMServiceProtocol {
    /// プロバイダー名
    var providerName: String { get }

    /// OCRテキストから名刺情報を構造化
    /// - Parameter ocrText: OCR抽出テキスト
    /// - Returns: 構造化された名刺データ
    func structureFromText(_ ocrText: String) async throws -> BusinessCardStructuredData

    /// 名刺画像から情報を構造化（精度優先モード用）
    /// - Parameters:
    ///   - imageData: 名刺画像データ（JPEG）
    ///   - ocrText: 補助的なOCRテキスト（オプション）
    /// - Returns: 構造化された名刺データ
    func structureFromImage(_ imageData: Data, ocrText: String?) async throws -> BusinessCardStructuredData

    /// 現在のモードに応じて構造化を実行
    /// - Parameters:
    ///   - image: 名刺画像
    ///   - ocrText: OCRテキスト
    ///   - mode: プライバシーモード
    /// - Returns: 構造化された名刺データ
    func structure(image: UIImage, ocrText: String, mode: LLMPrivacyMode) async throws -> BusinessCardStructuredData
}

// MARK: - Default Implementation

extension LLMServiceProtocol {
    /// モードに応じた構造化のデフォルト実装
    func structure(image: UIImage, ocrText: String, mode: LLMPrivacyMode) async throws -> BusinessCardStructuredData {
        switch mode {
        case .privacyFirst:
            return try await structureFromText(ocrText)
        case .accuracyFirst:
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw LLMServiceError.imageEncodingFailed
            }
            return try await structureFromImage(imageData, ocrText: ocrText)
        }
    }
}

// MARK: - BusinessCardStructuredData

/// LLMから返される構造化された名刺データ。
/// すべてのLLMプロバイダーで共通のレスポンス形式。
struct BusinessCardStructuredData: Codable, Sendable {
    let name: String?
    let nameReading: String?
    let company: String?
    let department: String?
    let title: String?
    let phoneNumbers: [String]?
    let emails: [String]?
    let address: String?
    let website: String?

    /// 空のデータを生成
    static var empty: BusinessCardStructuredData {
        BusinessCardStructuredData(
            name: nil,
            nameReading: nil,
            company: nil,
            department: nil,
            title: nil,
            phoneNumbers: nil,
            emails: nil,
            address: nil,
            website: nil
        )
    }

    /// 名前または会社名が存在するか
    var hasNameOrCompany: Bool {
        (name != nil && !name!.isEmpty) || (company != nil && !company!.isEmpty)
    }
}

// MARK: - LLMProvider

/// サポートされるLLMプロバイダー
enum LLMProvider: String, CaseIterable, Codable, Sendable {
    case claude = "claude"
    case chatgpt = "chatgpt"
    case gemini = "gemini"
    case perplexity = "perplexity"

    /// 表示名
    var displayName: String {
        switch self {
        case .claude:
            return "Claude (Anthropic)"
        case .chatgpt:
            return "ChatGPT (OpenAI)"
        case .gemini:
            return "Gemini (Google)"
        case .perplexity:
            return "Perplexity"
        }
    }

    /// アイコン名（SF Symbols）
    var iconName: String {
        switch self {
        case .claude:
            return "brain.head.profile"
        case .chatgpt:
            return "bubble.left.and.bubble.right"
        case .gemini:
            return "sparkles"
        case .perplexity:
            return "magnifyingglass.circle"
        }
    }

    /// APIキーのプレースホルダー
    var apiKeyPlaceholder: String {
        switch self {
        case .claude:
            return "sk-ant-..."
        case .chatgpt:
            return "sk-..."
        case .gemini:
            return "AIza..."
        case .perplexity:
            return "pplx-..."
        }
    }

    /// APIキー取得のヘルプURL
    var apiKeyHelpURL: URL? {
        switch self {
        case .claude:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .chatgpt:
            return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:
            return URL(string: "https://aistudio.google.com/app/apikey")
        case .perplexity:
            return URL(string: "https://www.perplexity.ai/settings/api")
        }
    }

    /// 画像入力をサポートするか
    var supportsImageInput: Bool {
        switch self {
        case .claude, .chatgpt, .gemini:
            return true
        case .perplexity:
            return false
        }
    }
}

// MARK: - LLMConnectionMode

/// LLM接続モード
enum LLMConnectionMode: String, CaseIterable, Codable, Sendable {
    /// AI構造化を使用しない
    case none = "none"
    /// Akkuratサブスクリプション経由（将来の有料版用）
    case akkuratSubscription = "akkurat"
    /// ユーザー自身のAPIキーを使用
    case selfApiKey = "self"

    /// 表示名
    var localizedName: String {
        switch self {
        case .none:
            return String(localized: "llm.mode.none")
        case .akkuratSubscription:
            return String(localized: "llm.mode.akkurat")
        case .selfApiKey:
            return String(localized: "llm.mode.selfApiKey")
        }
    }

    /// 説明
    var localizedDescription: String {
        switch self {
        case .none:
            return String(localized: "llm.mode.none.description")
        case .akkuratSubscription:
            return String(localized: "llm.mode.akkurat.description")
        case .selfApiKey:
            return String(localized: "llm.mode.selfApiKey.description")
        }
    }
}

// MARK: - LLMPrivacyMode

/// プライバシーモード
enum LLMPrivacyMode: String, CaseIterable, Codable, Sendable {
    /// プライバシー優先：テキストのみ送信
    case privacyFirst = "privacy"
    /// 精度優先：画像も送信
    case accuracyFirst = "accuracy"

    /// 表示名
    var localizedName: String {
        switch self {
        case .privacyFirst:
            return String(localized: "settings.aiMode.privacy")
        case .accuracyFirst:
            return String(localized: "settings.aiMode.accuracy")
        }
    }

    /// 説明
    var localizedDescription: String {
        switch self {
        case .privacyFirst:
            return String(localized: "settings.aiMode.privacy.description")
        case .accuracyFirst:
            return String(localized: "settings.aiMode.accuracy.description")
        }
    }
}

// MARK: - LLMServiceError

/// LLMサービス共通エラー
enum LLMServiceError: LocalizedError, Sendable {
    case apiKeyNotFound
    case imageEncodingFailed
    case networkError(Error)
    case unauthorized
    case rateLimited
    case badRequest(String)
    case serverError(Int, message: String?)
    case invalidResponse
    case parsingFailed
    case timeout
    case providerNotSupported
    case imageNotSupported

    var errorDescription: String? {
        switch self {
        case .apiKeyNotFound:
            return String(localized: "error.apiKey")
        case .imageEncodingFailed:
            return String(localized: "error.generic")
        case .networkError:
            return String(localized: "error.network")
        case .unauthorized:
            return String(localized: "error.apiKey")
        case .rateLimited:
            return String(localized: "error.rateLimit")
        case .badRequest(let message):
            return "API Error: \(message)"
        case .serverError(let code, let message):
            if let message = message {
                return "Server Error (\(code)): \(message)"
            }
            return String(localized: "error.generic")
        case .invalidResponse:
            return String(localized: "error.generic")
        case .parsingFailed:
            return String(localized: "error.generic")
        case .timeout:
            return String(localized: "error.timeout")
        case .providerNotSupported:
            return String(localized: "error.generic")
        case .imageNotSupported:
            return String(localized: "llm.error.imageNotSupported")
        }
    }
}
