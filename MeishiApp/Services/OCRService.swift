import Foundation
import Vision
import UIKit
import os.log

// MARK: - OCRService

/// Apple Vision Frameworkを使用したオンデバイスOCRサービス。
/// 名刺画像からテキストを抽出する。
actor OCRService {
    // MARK: - Singleton

    static let shared = OCRService()

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "OCR")

    /// OCR言語の優先順位（ユーザー設定から読み込み）
    var recognitionLanguages: [String] {
        get {
            UserDefaults.standard.array(forKey: "ocrLanguages") as? [String] ?? ["ja", "en", "zh-Hans", "zh-Hant", "ko"]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "ocrLanguages")
        }
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// 画像からテキストを抽出
    /// - Parameter image: OCR対象の画像
    /// - Returns: 抽出されたテキスト
    func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    self.logger.error("OCR error: \(error.localizedDescription)")
                    continuation.resume(throwing: OCRError.recognitionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let recognizedText = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                self.logger.info("OCR completed: \(recognizedText.count) characters")
                continuation.resume(returning: recognizedText)
            }

            // OCR設定
            request.recognitionLevel = .accurate
            request.recognitionLanguages = recognitionLanguages
            request.usesLanguageCorrection = true

            // iOS 16+で利用可能な自動言語検出
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                self.logger.error("OCR handler error: \(error.localizedDescription)")
                continuation.resume(throwing: OCRError.recognitionFailed(error))
            }
        }
    }

    /// 名刺の表面と裏面からテキストを抽出
    /// - Parameters:
    ///   - frontImage: 名刺の表面画像
    ///   - backImage: 名刺の裏面画像（オプション）
    /// - Returns: 表面と裏面のOCRテキスト
    func recognizeBusinessCard(
        frontImage: UIImage,
        backImage: UIImage? = nil
    ) async throws -> (front: String, back: String?) {
        logger.info("Starting business card OCR")

        let frontText = try await recognizeText(from: frontImage)

        var backText: String?
        if let backImage = backImage {
            backText = try await recognizeText(from: backImage)
        }

        return (frontText, backText)
    }

    /// サポートされている言語のリストを取得
    func getSupportedLanguages() -> [(code: String, name: String)] {
        // Vision Frameworkがサポートする主要言語
        return [
            ("ja", "日本語"),
            ("en", "English"),
            ("zh-Hans", "简体中文"),
            ("zh-Hant", "繁體中文"),
            ("ko", "한국어"),
            ("de", "Deutsch"),
            ("fr", "Français"),
            ("es", "Español"),
            ("it", "Italiano"),
            ("pt", "Português"),
            ("ru", "Русский"),
            ("sv", "Svenska"),
            ("nl", "Nederlands"),
            ("pl", "Polski"),
            ("da", "Dansk"),
            ("fi", "Suomi"),
            ("no", "Norsk"),
            ("cs", "Čeština"),
            ("hu", "Magyar"),
            ("tr", "Türkçe"),
            ("vi", "Tiếng Việt"),
            ("th", "ไทย"),
            ("ar", "العربية"),
            ("he", "עברית")
        ]
    }
}

// MARK: - OCRError

enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed(Error)
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return String(localized: "ocr.failed")
        case .recognitionFailed(let error):
            return "\(String(localized: "ocr.failed")): \(error.localizedDescription)"
        case .noTextFound:
            return String(localized: "ocr.noTextFound")
        }
    }
}

// MARK: - TextStructuringService

/// OCRテキストから名刺情報を構造化するサービス（手動構造化の自動推定部分）。
actor TextStructuringService {
    // MARK: - Singleton

    static let shared = TextStructuringService()

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "TextStructuring")

    // MARK: - Regex Patterns

    /// 電話番号パターン（日本の電話番号形式）
    private let phonePatterns: [NSRegularExpression] = {
        let patterns = [
            // 固定電話: 03-1234-5678, 03(1234)5678
            #"(?:0\d{1,4})[-(（]?\d{1,4}[-)）]?\d{3,4}"#,
            // 携帯電話: 090-1234-5678
            #"(?:090|080|070|050)[-(]?\d{4}[-)　]?\d{4}"#,
            // 国際形式: +81-3-1234-5678
            #"\+\d{1,3}[-(]?\d{1,4}[-)　]?\d{1,4}[-)　]?\d{3,4}"#,
            // スペース区切り: 03 1234 5678
            #"0\d{1,4}\s\d{1,4}\s\d{3,4}"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    /// メールアドレスパターン
    private let emailPattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            options: [.caseInsensitive]
        )
    }()

    /// URLパターン
    private let urlPattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"(?:https?://)?(?:www\.)?[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z]{2,}(?:/[^\s]*)?"#,
            options: [.caseInsensitive]
        )
    }()

    /// 郵便番号パターン（日本）
    private let postalCodePattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"〒?\s*\d{3}[-ー－]?\d{4}"#,
            options: []
        )
    }()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// OCRテキストから情報を自動推定
    /// - Parameter text: OCRテキスト
    /// - Returns: 推定された構造化データ
    func extractStructuredData(from text: String) -> ExtractedCardData {
        logger.info("Extracting structured data from OCR text")

        var data = ExtractedCardData()

        // 電話番号を抽出
        data.phoneNumbers = extractPhoneNumbers(from: text)

        // メールアドレスを抽出
        data.emails = extractEmails(from: text)

        // URLを抽出
        data.website = extractWebsite(from: text)

        // 住所を抽出（郵便番号を含む行）
        data.address = extractAddress(from: text)

        logger.info("Extracted: \(data.phoneNumbers.count) phones, \(data.emails.count) emails")

        return data
    }

    // MARK: - Private Methods

    /// 電話番号を抽出
    private func extractPhoneNumbers(from text: String) -> [String] {
        var phoneNumbers: [String] = []

        for pattern in phonePatterns {
            let range = NSRange(text.startIndex..., in: text)
            let matches = pattern.matches(in: text, options: [], range: range)

            for match in matches {
                if let range = Range(match.range, in: text) {
                    let phoneNumber = String(text[range])
                        .replacingOccurrences(of: "（", with: "-")
                        .replacingOccurrences(of: "）", with: "-")
                        .replacingOccurrences(of: "(", with: "-")
                        .replacingOccurrences(of: ")", with: "-")
                        .replacingOccurrences(of: " ", with: "-")
                        .replacingOccurrences(of: "　", with: "-")

                    // 重複チェック
                    let normalized = phoneNumber.replacingOccurrences(of: "-", with: "")
                    if !phoneNumbers.contains(where: { $0.replacingOccurrences(of: "-", with: "") == normalized }) {
                        phoneNumbers.append(phoneNumber)
                    }
                }
            }
        }

        return phoneNumbers
    }

    /// メールアドレスを抽出
    private func extractEmails(from text: String) -> [String] {
        guard let pattern = emailPattern else { return [] }

        var emails: [String] = []
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, options: [], range: range)

        for match in matches {
            if let range = Range(match.range, in: text) {
                let email = String(text[range]).lowercased()
                if !emails.contains(email) {
                    emails.append(email)
                }
            }
        }

        return emails
    }

    /// URLを抽出
    private func extractWebsite(from text: String) -> String? {
        guard let pattern = urlPattern else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        if let match = pattern.firstMatch(in: text, options: [], range: range),
           let range = Range(match.range, in: text) {
            var url = String(text[range])

            // メールアドレスを除外
            if url.contains("@") { return nil }

            // プロトコルがない場合は追加
            if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
                url = "https://" + url
            }

            return url
        }

        return nil
    }

    /// 住所を抽出
    private func extractAddress(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)

        // 郵便番号を含む行を検索
        for (index, line) in lines.enumerated() {
            if let pattern = postalCodePattern {
                let range = NSRange(line.startIndex..., in: line)
                if pattern.firstMatch(in: line, options: [], range: range) != nil {
                    // 郵便番号の行と次の行を結合して住所とする
                    var address = line.trimmingCharacters(in: .whitespaces)
                    if index + 1 < lines.count {
                        let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                        // 次の行が住所の続きっぽければ追加
                        if !nextLine.isEmpty &&
                            !nextLine.contains("@") &&
                            !nextLine.contains("TEL") &&
                            !nextLine.contains("FAX") &&
                            !nextLine.contains("http") {
                            address += " " + nextLine
                        }
                    }
                    return address
                }
            }
        }

        // 「都」「道」「府」「県」を含む行を検索
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("都") || trimmed.contains("道") ||
               trimmed.contains("府") || trimmed.contains("県") {
                // 電話番号やメールでないことを確認
                if !trimmed.contains("@") && !trimmed.contains("TEL") &&
                   !trimmed.contains("FAX") && !trimmed.hasPrefix("0") {
                    return trimmed
                }
            }
        }

        return nil
    }
}

// MARK: - ExtractedCardData

/// OCRテキストから自動推定された名刺データ。
struct ExtractedCardData {
    var name: String?
    var nameReading: String?
    var company: String?
    var department: String?
    var title: String?
    var phoneNumbers: [String] = []
    var emails: [String] = []
    var address: String?
    var website: String?
}
