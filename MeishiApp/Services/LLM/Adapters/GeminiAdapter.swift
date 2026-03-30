import Foundation
import UIKit
import os.log

// MARK: - GeminiAdapter

/// Gemini API（Google）用のアダプター
actor GeminiAdapter: LLMServiceProtocol {
    // MARK: - Constants

    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private static let modelName = "gemini-2.0-flash"
    private static let maxOutputTokens = 1024
    private static let timeoutInterval: TimeInterval = 30

    // MARK: - Properties

    private let apiKey: String
    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "GeminiAdapter")

    nonisolated let providerName: String = "Gemini"

    // MARK: - Initialization

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - LLMServiceProtocol

    func structureFromText(_ ocrText: String) async throws -> BusinessCardStructuredData {
        logger.info("Starting text-based structuring")

        let prompt = Self.buildTextPrompt(ocrText: ocrText)

        let requestBody = GenerateContentRequest(
            contents: [
                Content(parts: [Part.text(prompt)])
            ],
            generationConfig: GenerationConfig(
                maxOutputTokens: Self.maxOutputTokens,
                responseMimeType: "application/json"
            )
        )

        return try await sendRequest(requestBody)
    }

    func structureFromImage(_ imageData: Data, ocrText: String?) async throws -> BusinessCardStructuredData {
        logger.info("Starting image-based structuring")

        let base64Image = imageData.base64EncodedString()
        logger.info("Image base64 size: \(base64Image.count) chars")

        let textPrompt = Self.buildImagePrompt()

        let requestBody = GenerateContentRequest(
            contents: [
                Content(parts: [
                    Part.inlineData(InlineData(mimeType: "image/jpeg", data: base64Image)),
                    Part.text(textPrompt)
                ])
            ],
            generationConfig: GenerationConfig(
                maxOutputTokens: Self.maxOutputTokens,
                responseMimeType: "application/json"
            )
        )

        return try await sendRequest(requestBody)
    }

    // MARK: - Private Methods

    private func sendRequest(_ request: GenerateContentRequest, retryCount: Int = 0) async throws -> BusinessCardStructuredData {
        let urlString = "\(Self.baseURL)/\(Self.modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw LLMServiceError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Self.timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMServiceError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                return try parseResponse(data)

            case 401, 403:
                logger.error("API key invalid")
                throw LLMServiceError.unauthorized

            case 429:
                if retryCount < 3 {
                    let delay = pow(2.0, Double(retryCount))
                    logger.warning("Rate limited, retrying in \(delay) seconds")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await sendRequest(request, retryCount: retryCount + 1)
                }
                throw LLMServiceError.rateLimited

            case 400:
                if let errorResponse = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data) {
                    logger.error("Bad request: \(errorResponse.error.message)")
                    throw LLMServiceError.badRequest(errorResponse.error.message)
                }
                throw LLMServiceError.badRequest("Unknown error")

            case 500...599:
                if retryCount < 3 {
                    let delay = pow(2.0, Double(retryCount))
                    logger.warning("Server error, retrying in \(delay) seconds")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await sendRequest(request, retryCount: retryCount + 1)
                }
                throw LLMServiceError.serverError(httpResponse.statusCode, message: nil)

            default:
                if let errorResponse = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data) {
                    logger.error("API error (\(httpResponse.statusCode)): \(errorResponse.error.message)")
                    throw LLMServiceError.serverError(httpResponse.statusCode, message: errorResponse.error.message)
                }
                throw LLMServiceError.serverError(httpResponse.statusCode, message: nil)
            }
        } catch let error as LLMServiceError {
            throw error
        } catch {
            if retryCount < 3 {
                let delay = pow(2.0, Double(retryCount))
                logger.warning("Network error, retrying in \(delay) seconds: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await sendRequest(request, retryCount: retryCount + 1)
            }
            throw LLMServiceError.networkError(error)
        }
    }

    private func parseResponse(_ data: Data) throws -> BusinessCardStructuredData {
        let decoder = JSONDecoder()
        let response = try decoder.decode(GenerateContentResponse.self, from: data)

        guard let candidate = response.candidates?.first,
              let part = candidate.content.parts.first,
              case .text(let text) = part else {
            throw LLMServiceError.parsingFailed
        }

        let jsonString = Self.extractJSON(from: text)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw LLMServiceError.parsingFailed
        }

        do {
            let structuredData = try decoder.decode(BusinessCardStructuredData.self, from: jsonData)
            logger.info("Successfully parsed structured data")
            return structuredData
        } catch {
            logger.error("JSON parsing failed: \(error.localizedDescription)")
            throw LLMServiceError.parsingFailed
        }
    }

    // MARK: - Static Helpers

    private static func buildTextPrompt(ocrText: String) -> String {
        """
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
    }

    private static func buildImagePrompt() -> String {
        """
        この名刺画像から情報を読み取り、JSON形式で構造化してください。
        フィールド: name, nameReading, company, department, title, phoneNumbers(配列), emails(配列), address, website

        注意事項:
        - 名刺に書かれている言語をそのまま使用してください（英語の名刺は英語のまま、日本語の名刺は日本語のまま）
        - nameReadingは名刺にふりがな（ひらがな・カタカナ・ローマ字など）が明示的に記載されている場合のみ入力。推測や自動生成は絶対にしないでください。記載がなければnull
        - phoneNumbersとemailsは配列として返してください
        - 不明なフィールドはnullにしてください
        - JSON以外の説明は不要です
        """
    }

    private static func extractJSON(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

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
}

// MARK: - API Models

private struct GenerateContentRequest: Encodable {
    let contents: [Content]
    let generationConfig: GenerationConfig?
}

private struct Content: Encodable {
    let parts: [Part]
}

private enum Part: Encodable {
    case text(String)
    case inlineData(InlineData)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(text, forKey: .text)
        case .inlineData(let inlineData):
            try container.encode(inlineData, forKey: .inlineData)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct InlineData: Encodable {
    let mimeType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct GenerationConfig: Encodable {
    let maxOutputTokens: Int
    let responseMimeType: String?

    enum CodingKeys: String, CodingKey {
        case maxOutputTokens = "maxOutputTokens"
        case responseMimeType = "responseMimeType"
    }
}

private struct GenerateContentResponse: Decodable {
    let candidates: [Candidate]?

    struct Candidate: Decodable {
        let content: ResponseContent
    }

    struct ResponseContent: Decodable {
        let parts: [ResponsePart]
    }
}

private enum ResponsePart: Decodable {
    case text(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let text = try? container.decode(String.self, forKey: .text) {
            self = .text(text)
        } else {
            self = .other
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text
    }
}

private struct GeminiErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let code: Int
        let message: String
        let status: String?
    }
}
