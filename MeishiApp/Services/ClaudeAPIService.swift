import Foundation
import UIKit
import os.log

// MARK: - ClaudeAPIService

/// Claude APIを使用したAI構造化サービス（有料版機能）。
/// プライバシー優先モード（テキストのみ）と精度優先モード（画像含む）を提供。
actor ClaudeAPIService {
    // MARK: - Types

    enum StructuringMode: String, CaseIterable {
        case privacyFirst = "privacy"   // OCRテキストのみ送信
        case accuracyFirst = "accuracy" // 名刺画像も送信

        var localizedName: String {
            switch self {
            case .privacyFirst:
                return String(localized: "settings.aiMode.privacy")
            case .accuracyFirst:
                return String(localized: "settings.aiMode.accuracy")
            }
        }

        var description: String {
            switch self {
            case .privacyFirst:
                return String(localized: "settings.aiMode.privacy.description")
            case .accuracyFirst:
                return String(localized: "settings.aiMode.accuracy.description")
            }
        }
    }

    // MARK: - Constants

    private static let apiEndpoint = "https://api.anthropic.com/v1/messages"
    private static let modelName = "claude-sonnet-4-20250514"
    private static let maxTokens = 1024
    private static let timeoutInterval: TimeInterval = 30

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "ClaudeAPI")

    /// 現在の構造化モード
    var currentMode: StructuringMode {
        let rawValue = UserDefaults.standard.string(forKey: "aiStructuringMode") ?? "privacy"
        return StructuringMode(rawValue: rawValue) ?? .privacyFirst
    }

    /// 構造化モードを設定
    func setMode(_ mode: StructuringMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "aiStructuringMode")
    }

    /// AI構造化の初回説明を表示済みか
    var hasShownDisclosure: Bool {
        get { UserDefaults.standard.bool(forKey: "hasShownAIDisclosure") }
        set { UserDefaults.standard.set(newValue, forKey: "hasShownAIDisclosure") }
    }

    // MARK: - Singleton

    static let shared = ClaudeAPIService()

    private init() {}

    // MARK: - API Key Management

    private static let apiKeyKey = "claudeAPIKey"

    /// APIキーが設定されているか
    var hasAPIKey: Bool {
        getAPIKey() != nil
    }

    /// APIキーを取得
    private func getAPIKey() -> String? {
        // 1. UserDefaultsから取得（設定画面で入力）
        if let key = UserDefaults.standard.string(forKey: Self.apiKeyKey), !key.isEmpty {
            return key
        }

        // 2. 環境変数から取得（開発用）
        if let key = ProcessInfo.processInfo.environment["CLAUDE_API_KEY"], !key.isEmpty {
            return key
        }

        return nil
    }

    /// APIキーを保存
    func setAPIKey(_ key: String?) {
        if let key = key, !key.isEmpty {
            UserDefaults.standard.set(key, forKey: Self.apiKeyKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.apiKeyKey)
        }
    }

    /// 保存されているAPIキーを取得（設定画面表示用）
    func getSavedAPIKey() -> String? {
        UserDefaults.standard.string(forKey: Self.apiKeyKey)
    }

    // MARK: - Public Methods

    /// OCRテキストからAI構造化（プライバシー優先モード）
    /// - Parameter ocrText: OCR抽出テキスト
    /// - Returns: 構造化されたデータ
    func structureFromText(_ ocrText: String) async throws -> StructuredCardData {
        guard let apiKey = getAPIKey() else {
            throw ClaudeAPIError.apiKeyNotFound
        }

        logger.info("Starting text-based structuring")

        let prompt = """
        以下は名刺のOCRテキストです。JSON形式で構造化してください。
        フィールド: name, nameReading, company, department, title, phoneNumbers(配列), emails(配列), address, website

        注意事項:
        - 名刺に書かれている言語をそのまま使用してください（英語の名刺は英語のまま、日本語の名刺は日本語のまま）
        - nameReadingは名刺にふりがな（ひらがな・カタカナ・ローマ字など）が明示的に記載されている場合のみ入力。推測や自動生成は絶対にしないでください。記載がなければnull
        - phoneNumbersとemailsは配列として返してください
        - 不明なフィールドはnullにしてください
        - JSON以外の説明は不要です

        OCRテキスト:
        \(ocrText)
        """

        let requestBody = APIRequest(
            model: Self.modelName,
            maxTokens: Self.maxTokens,
            messages: [
                Message(role: "user", content: .text(prompt))
            ]
        )

        return try await sendRequest(requestBody, apiKey: apiKey)
    }

    /// 名刺画像からAI構造化（精度優先モード）
    /// - Parameters:
    ///   - image: 名刺画像
    ///   - ocrText: 補助的なOCRテキスト（オプション）
    /// - Returns: 構造化されたデータ
    func structureFromImage(_ image: UIImage, ocrText: String? = nil) async throws -> StructuredCardData {
        guard let apiKey = getAPIKey() else {
            throw ClaudeAPIError.apiKeyNotFound
        }

        // 画像を最大4000ピクセルにリサイズ（API制限は8000だが余裕を持たせる）
        // 実際のピクセルサイズをログに出力（UIImage.sizeはポイント、scale倍がピクセル）
        let originalPixelWidth = Int(image.size.width * image.scale)
        let originalPixelHeight = Int(image.size.height * image.scale)
        let resizedImage = resizeImageIfNeeded(image, maxDimension: 4000)
        let resizedPixelWidth = Int(resizedImage.size.width * resizedImage.scale)
        let resizedPixelHeight = Int(resizedImage.size.height * resizedImage.scale)

        logger.info("Image pixels: \(originalPixelWidth)x\(originalPixelHeight) -> \(resizedPixelWidth)x\(resizedPixelHeight)")

        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw ClaudeAPIError.imageEncodingFailed
        }

        let base64Image = imageData.base64EncodedString()

        logger.info("Starting image-based structuring, base64 size: \(base64Image.count) chars")

        let textPrompt = """
        この名刺画像から情報を読み取り、JSON形式で構造化してください。
        フィールド: name, nameReading, company, department, title, phoneNumbers(配列), emails(配列), address, website

        注意事項:
        - 名刺に書かれている言語をそのまま使用してください（英語の名刺は英語のまま、日本語の名刺は日本語のまま）
        - nameReadingは名刺にふりがな（ひらがな・カタカナ・ローマ字など）が明示的に記載されている場合のみ入力。推測や自動生成は絶対にしないでください。記載がなければnull
        - phoneNumbersとemailsは配列として返してください
        - 不明なフィールドはnullにしてください
        - JSON以外の説明は不要です
        """

        let content: [ContentBlock] = [
            .image(ImageContent(
                source: ImageSource(
                    type: "base64",
                    mediaType: "image/jpeg",
                    data: base64Image
                )
            )),
            .text(textPrompt)
        ]

        let requestBody = APIRequest(
            model: Self.modelName,
            maxTokens: Self.maxTokens,
            messages: [
                Message(role: "user", content: .blocks(content))
            ]
        )

        return try await sendRequest(requestBody, apiKey: apiKey)
    }

    /// 現在のモードに応じて構造化を実行
    /// - Parameters:
    ///   - image: 名刺画像
    ///   - ocrText: OCRテキスト
    /// - Returns: 構造化されたデータ
    func structure(image: UIImage, ocrText: String) async throws -> StructuredCardData {
        let mode = currentMode
        logger.info("Current mode: \(mode.rawValue)")
        switch mode {
        case .privacyFirst:
            logger.info("Using privacy-first mode (text only)")
            return try await structureFromText(ocrText)
        case .accuracyFirst:
            logger.info("Using accuracy-first mode (with image)")
            return try await structureFromImage(image, ocrText: ocrText)
        }
    }

    // MARK: - Private Methods

    private func sendRequest(_ request: APIRequest, apiKey: String, retryCount: Int = 0) async throws -> StructuredCardData {
        var urlRequest = URLRequest(url: URL(string: Self.apiEndpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Self.timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClaudeAPIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                return try parseResponse(data)

            case 401:
                logger.error("API key invalid")
                throw ClaudeAPIError.unauthorized

            case 429:
                // レート制限 - リトライ
                if retryCount < 3 {
                    let delay = pow(2.0, Double(retryCount))
                    logger.warning("Rate limited, retrying in \(delay) seconds")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await sendRequest(request, apiKey: apiKey, retryCount: retryCount + 1)
                }
                throw ClaudeAPIError.rateLimited

            case 400:
                // Bad Request - リクエストの形式が不正
                if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                    logger.error("Bad request: \(errorResponse.error.message)")
                    throw ClaudeAPIError.badRequest(errorResponse.error.message)
                }
                logger.error("Bad request with unknown error")
                throw ClaudeAPIError.badRequest("Unknown error")

            case 500...599:
                // サーバーエラー - リトライ
                if retryCount < 3 {
                    let delay = pow(2.0, Double(retryCount))
                    logger.warning("Server error, retrying in \(delay) seconds")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await sendRequest(request, apiKey: apiKey, retryCount: retryCount + 1)
                }
                throw ClaudeAPIError.serverError(httpResponse.statusCode)

            default:
                // その他のエラー - エラーレスポンスをパース
                if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                    logger.error("API error (\(httpResponse.statusCode)): \(errorResponse.error.message)")
                    throw ClaudeAPIError.serverError(httpResponse.statusCode, message: errorResponse.error.message)
                }
                logger.error("Unexpected status code: \(httpResponse.statusCode)")
                throw ClaudeAPIError.serverError(httpResponse.statusCode, message: nil)
            }
        } catch let error as ClaudeAPIError {
            throw error
        } catch {
            if retryCount < 3 {
                let delay = pow(2.0, Double(retryCount))
                logger.warning("Network error, retrying in \(delay) seconds: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await sendRequest(request, apiKey: apiKey, retryCount: retryCount + 1)
            }
            throw ClaudeAPIError.networkError(error)
        }
    }

    private func parseResponse(_ data: Data) throws -> StructuredCardData {
        let decoder = JSONDecoder()

        // APIレスポンスをパース
        let response = try decoder.decode(APIResponse.self, from: data)

        // content[0].text からJSONを抽出
        guard let textContent = response.content.first,
              case .text(let text) = textContent else {
            throw ClaudeAPIError.parsingFailed
        }

        // JSONを抽出（```json ... ``` で囲まれている場合も対応）
        let jsonString = extractJSON(from: text)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ClaudeAPIError.parsingFailed
        }

        do {
            let structuredData = try decoder.decode(StructuredCardData.self, from: jsonData)
            logger.info("Successfully parsed structured data")
            return structuredData
        } catch {
            logger.error("JSON parsing failed: \(error.localizedDescription)")
            throw ClaudeAPIError.parsingFailed
        }
    }

    private func extractJSON(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // ```json ... ``` を除去
        if result.hasPrefix("```json") {
            result = String(result.dropFirst(7))
        } else if result.hasPrefix("```") {
            result = String(result.dropFirst(3))
        }

        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 画像が指定サイズを超える場合にリサイズ（ピクセルベース）
    nonisolated private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        // 実際のピクセルサイズを取得（scaleを考慮）
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale

        // 両方の辺が制限内ならそのまま返す
        if pixelWidth <= maxDimension && pixelHeight <= maxDimension {
            return image
        }

        // アスペクト比を維持してリサイズ
        let scale: CGFloat
        if pixelWidth > pixelHeight {
            scale = maxDimension / pixelWidth
        } else {
            scale = maxDimension / pixelHeight
        }

        // 新しいピクセルサイズ
        let newPixelWidth = pixelWidth * scale
        let newPixelHeight = pixelHeight * scale

        // UIGraphicsImageRendererはポイントで描画するので、scale=1でピクセルサイズと一致させる
        let newSize = CGSize(width: newPixelWidth, height: newPixelHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // ピクセルベースで描画

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized
    }
}

// MARK: - API Request/Response Models

private struct APIRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
    }
}

private struct Message: Encodable {
    let role: String
    let content: MessageContent
}

private enum MessageContent: Encodable {
    case text(String)
    case blocks([ContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

private enum ContentBlock: Encodable {
    case text(String)
    case image(ImageContent)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let imageContent):
            try container.encode("image", forKey: .type)
            try container.encode(imageContent.source, forKey: .source)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, source
    }
}

private struct ImageContent: Encodable {
    let source: ImageSource
}

private struct ImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct APIResponse: Decodable {
    let content: [ResponseContent]
}

private enum ResponseContent: Decodable {
    case text(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        if type == "text" {
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        } else {
            self = .other
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text
    }
}

private struct APIErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let type: String
        let message: String
    }
}

// MARK: - StructuredCardData

/// Claude APIから返される構造化された名刺データ。
struct StructuredCardData: Decodable {
    let name: String?
    let nameReading: String?
    let company: String?
    let department: String?
    let title: String?
    let phoneNumbers: [String]?
    let emails: [String]?
    let address: String?
    let website: String?
}

// MARK: - ClaudeAPIError

enum ClaudeAPIError: LocalizedError {
    case apiKeyNotFound
    case imageEncodingFailed
    case networkError(Error)
    case unauthorized
    case rateLimited
    case badRequest(String)
    case serverError(Int, message: String? = nil)
    case invalidResponse
    case parsingFailed
    case timeout

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
        }
    }
}
