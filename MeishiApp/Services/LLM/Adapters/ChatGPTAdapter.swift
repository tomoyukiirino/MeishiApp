import Foundation
import UIKit
import os.log

// MARK: - ChatGPTAdapter

/// ChatGPT API（OpenAI）用のアダプター
actor ChatGPTAdapter: LLMServiceProtocol {
    // MARK: - Constants

    private static let apiEndpoint = "https://api.openai.com/v1/chat/completions"
    private static let modelName = "gpt-4o"
    private static let maxTokens = 1024
    private static let timeoutInterval: TimeInterval = 30

    // MARK: - Properties

    private let apiKey: String
    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "ChatGPTAdapter")

    nonisolated let providerName: String = "ChatGPT"

    // MARK: - Initialization

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - LLMServiceProtocol

    func structureFromText(_ ocrText: String) async throws -> BusinessCardStructuredData {
        logger.info("Starting text-based structuring")

        let prompt = Self.buildTextPrompt(ocrText: ocrText)

        let requestBody = ChatCompletionRequest(
            model: Self.modelName,
            messages: [
                ChatMessage(role: "user", content: .text(prompt))
            ],
            maxTokens: Self.maxTokens,
            responseFormat: ResponseFormat(type: "json_object")
        )

        return try await sendRequest(requestBody)
    }

    func structureFromImage(_ imageData: Data, ocrText: String?) async throws -> BusinessCardStructuredData {
        logger.info("Starting image-based structuring")

        let base64Image = imageData.base64EncodedString()
        let imageURL = "data:image/jpeg;base64,\(base64Image)"
        logger.info("Image base64 size: \(base64Image.count) chars")

        let textPrompt = Self.buildImagePrompt()

        let content: [ContentPart] = [
            .image(ImageURLContent(imageUrl: ImageURL(url: imageURL))),
            .text(textPrompt)
        ]

        let requestBody = ChatCompletionRequest(
            model: Self.modelName,
            messages: [
                ChatMessage(role: "user", content: .parts(content))
            ],
            maxTokens: Self.maxTokens,
            responseFormat: ResponseFormat(type: "json_object")
        )

        return try await sendRequest(requestBody)
    }

    // MARK: - Private Methods

    private func sendRequest(_ request: ChatCompletionRequest, retryCount: Int = 0) async throws -> BusinessCardStructuredData {
        var urlRequest = URLRequest(url: URL(string: Self.apiEndpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Self.timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

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

            case 401:
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
                if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
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
                if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
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
        let response = try decoder.decode(ChatCompletionResponse.self, from: data)

        guard let choice = response.choices.first,
              let content = choice.message.content else {
            throw LLMServiceError.parsingFailed
        }

        let jsonString = Self.extractJSON(from: content)

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

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: MessageContent
}

private enum MessageContent: Encodable {
    case text(String)
    case parts([ContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

private enum ContentPart: Encodable {
    case text(String)
    case image(ImageURLContent)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let imageContent):
            try container.encode("image_url", forKey: .type)
            try container.encode(imageContent.imageUrl, forKey: .imageUrl)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
}

private struct ImageURLContent: Encodable {
    let imageUrl: ImageURL
}

private struct ImageURL: Encodable {
    let url: String
}

private struct ResponseFormat: Encodable {
    let type: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ResponseMessage
    }

    struct ResponseMessage: Decodable {
        let content: String?
    }
}

private struct OpenAIErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
        let type: String?
    }
}
