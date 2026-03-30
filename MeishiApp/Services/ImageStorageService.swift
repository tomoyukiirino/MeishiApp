import Foundation
import UIKit
import os.log

// MARK: - ImageStorageService

/// 画像のファイルシステム保存・読み込みを管理するサービス。
/// すべての画像に NSFileProtectionComplete を適用し、端末ロック中はアクセス不可にする。
actor ImageStorageService {
    // MARK: - Singleton

    static let shared = ImageStorageService()

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "ImageStorage")
    private let fileManager = FileManager.default

    /// 画像保存用のベースディレクトリ
    private var imagesDirectory: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent("images", isDirectory: true)
    }

    /// 名刺画像用ディレクトリ
    private var cardsDirectory: URL {
        imagesDirectory.appendingPathComponent("cards", isDirectory: true)
    }

    /// 顔写真用ディレクトリ
    private var facesDirectory: URL {
        imagesDirectory.appendingPathComponent("faces", isDirectory: true)
    }

    // MARK: - Initialization

    private init() {
        Task {
            await createDirectoriesIfNeeded()
        }
    }

    // MARK: - Directory Management

    /// 必要なディレクトリを作成
    private func createDirectoriesIfNeeded() {
        do {
            try fileManager.createDirectory(at: cardsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: facesDirectory, withIntermediateDirectories: true)

            // ディレクトリにFileProtectionを適用
            try setFileProtection(for: imagesDirectory)
            try setFileProtection(for: cardsDirectory)
            try setFileProtection(for: facesDirectory)

            logger.info("Images directories created successfully")
        } catch {
            logger.error("Failed to create images directories: \(error.localizedDescription)")
        }
    }

    /// ファイル/ディレクトリに NSFileProtectionComplete を設定
    private func setFileProtection(for url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    // MARK: - Card Image Operations

    /// 名刺の表面画像を保存
    /// - Parameters:
    ///   - image: 保存する画像
    ///   - cardId: 名刺のUUID
    /// - Returns: 保存された画像の相対パス
    func saveCardFrontImage(_ image: UIImage, cardId: UUID) async throws -> String {
        let filename = "\(cardId.uuidString)_front.jpg"
        let relativePath = "images/cards/\(filename)"
        let fullURL = cardsDirectory.appendingPathComponent(filename)

        try await saveImage(image, to: fullURL)
        logger.info("Saved card front image: \(relativePath)")

        return relativePath
    }

    /// 名刺の裏面画像を保存
    /// - Parameters:
    ///   - image: 保存する画像
    ///   - cardId: 名刺のUUID
    /// - Returns: 保存された画像の相対パス
    func saveCardBackImage(_ image: UIImage, cardId: UUID) async throws -> String {
        let filename = "\(cardId.uuidString)_back.jpg"
        let relativePath = "images/cards/\(filename)"
        let fullURL = cardsDirectory.appendingPathComponent(filename)

        try await saveImage(image, to: fullURL)
        logger.info("Saved card back image: \(relativePath)")

        return relativePath
    }

    /// 名刺画像を削除
    /// - Parameter cardId: 名刺のUUID
    func deleteCardImages(cardId: UUID) async throws {
        let frontFilename = "\(cardId.uuidString)_front.jpg"
        let backFilename = "\(cardId.uuidString)_back.jpg"

        let frontURL = cardsDirectory.appendingPathComponent(frontFilename)
        let backURL = cardsDirectory.appendingPathComponent(backFilename)

        if fileManager.fileExists(atPath: frontURL.path) {
            try fileManager.removeItem(at: frontURL)
            logger.info("Deleted card front image: \(frontFilename)")
        }

        if fileManager.fileExists(atPath: backURL.path) {
            try fileManager.removeItem(at: backURL)
            logger.info("Deleted card back image: \(backFilename)")
        }
    }

    // MARK: - Face Photo Operations

    /// 顔写真を保存
    /// - Parameters:
    ///   - image: 保存する画像
    ///   - personId: PersonのUUID
    /// - Returns: 保存された画像の相対パス
    func saveFacePhoto(_ image: UIImage, personId: UUID) async throws -> String {
        let filename = "\(personId.uuidString)_face.jpg"
        let relativePath = "images/faces/\(filename)"
        let fullURL = facesDirectory.appendingPathComponent(filename)

        try await saveImage(image, to: fullURL)
        logger.info("Saved face photo: \(relativePath)")

        return relativePath
    }

    /// 顔写真を削除
    /// - Parameter personId: PersonのUUID
    func deleteFacePhoto(personId: UUID) async throws {
        let filename = "\(personId.uuidString)_face.jpg"
        let fullURL = facesDirectory.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: fullURL.path) {
            try fileManager.removeItem(at: fullURL)
            logger.info("Deleted face photo: \(filename)")
        }
    }

    // MARK: - Image Loading

    /// 相対パスから画像を読み込み
    /// - Parameter relativePath: 画像の相対パス
    /// - Returns: 読み込んだUIImage、またはnil
    func loadImage(relativePath: String) async -> UIImage? {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fullURL = documentsURL.appendingPathComponent(relativePath)

        guard fileManager.fileExists(atPath: fullURL.path) else {
            logger.warning("Image not found: \(relativePath)")
            return nil
        }

        guard let data = try? Data(contentsOf: fullURL),
              let image = UIImage(data: data) else {
            logger.error("Failed to load image: \(relativePath)")
            return nil
        }

        return image
    }

    /// 名刺の表面画像を読み込み
    /// - Parameter cardId: 名刺のUUID
    /// - Returns: 読み込んだUIImage、またはnil
    func loadCardFrontImage(cardId: UUID) async -> UIImage? {
        let relativePath = "images/cards/\(cardId.uuidString)_front.jpg"
        return await loadImage(relativePath: relativePath)
    }

    /// 名刺の裏面画像を読み込み
    /// - Parameter cardId: 名刺のUUID
    /// - Returns: 読み込んだUIImage、またはnil
    func loadCardBackImage(cardId: UUID) async -> UIImage? {
        let relativePath = "images/cards/\(cardId.uuidString)_back.jpg"
        return await loadImage(relativePath: relativePath)
    }

    /// 顔写真を読み込み
    /// - Parameter personId: PersonのUUID
    /// - Returns: 読み込んだUIImage、またはnil
    func loadFacePhoto(personId: UUID) async -> UIImage? {
        let relativePath = "images/faces/\(personId.uuidString)_face.jpg"
        return await loadImage(relativePath: relativePath)
    }

    // MARK: - Private Methods

    /// 画像をJPEG形式で保存
    private func saveImage(_ image: UIImage, to url: URL) async throws {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw ImageStorageError.compressionFailed
        }

        try data.write(to: url, options: .atomic)

        // FileProtectionを適用
        try setFileProtection(for: url)
    }

    // MARK: - Utility Methods

    /// 画像のフルURLを取得
    func getFullURL(relativePath: String) -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent(relativePath)
    }

    /// 画像が存在するか確認
    func imageExists(relativePath: String) -> Bool {
        let fullURL = getFullURL(relativePath: relativePath)
        return fileManager.fileExists(atPath: fullURL.path)
    }

    /// 相対パスで指定された画像を削除
    /// - Parameter relativePath: 画像の相対パス
    func deleteImage(relativePath: String) {
        let fullURL = getFullURL(relativePath: relativePath)
        if fileManager.fileExists(atPath: fullURL.path) {
            do {
                try fileManager.removeItem(at: fullURL)
                logger.info("Deleted image: \(relativePath)")
            } catch {
                logger.error("Failed to delete image: \(relativePath), error: \(error.localizedDescription)")
            }
        }
    }

    /// すべての画像の合計サイズを取得（バイト単位）
    func getTotalImageSize() -> Int64 {
        var totalSize: Int64 = 0

        guard let enumerator = fileManager.enumerator(at: imagesDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return totalSize
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[.size] as? Int64 {
                totalSize += fileSize
            }
        }

        return totalSize
    }

    /// 画像の数を取得
    func getImageCount() -> (cards: Int, faces: Int) {
        var cardCount = 0
        var faceCount = 0

        if let cardFiles = try? fileManager.contentsOfDirectory(atPath: cardsDirectory.path) {
            cardCount = cardFiles.filter { $0.hasSuffix(".jpg") }.count
        }

        if let faceFiles = try? fileManager.contentsOfDirectory(atPath: facesDirectory.path) {
            faceCount = faceFiles.filter { $0.hasSuffix(".jpg") }.count
        }

        return (cardCount, faceCount)
    }
}

// MARK: - ImageStorageError

enum ImageStorageError: LocalizedError {
    case compressionFailed
    case saveFailed(Error)
    case deleteFailed(Error)
    case loadFailed(Error)
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return String(localized: "error.saveData")
        case .saveFailed(let error):
            return "\(String(localized: "error.saveData")): \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "\(String(localized: "error.deleteData")): \(error.localizedDescription)"
        case .loadFailed(let error):
            return "\(String(localized: "error.loadData")): \(error.localizedDescription)"
        case .fileNotFound:
            return String(localized: "error.loadData")
        }
    }
}
