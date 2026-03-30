import Foundation
import UIKit
import Vision
import CoreImage
import os.log

// MARK: - ImageProcessor

/// 画像のクロップ・傾き補正を行うユーティリティ。
/// 名刺の矩形検出と自動補正を担当する。
actor ImageProcessor {
    // MARK: - Singleton

    static let shared = ImageProcessor()

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "ImageProcessor")
    private let ciContext = CIContext()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// 画像から名刺の矩形を検出
    /// - Parameter image: 入力画像
    /// - Returns: 検出された矩形の情報（正規化座標）
    func detectRectangle(in image: UIImage) async throws -> DetectedRectangle? {
        guard let cgImage = image.cgImage else {
            throw ImageProcessorError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error = error {
                    self.logger.error("Rectangle detection error: \(error.localizedDescription)")
                    continuation.resume(throwing: ImageProcessorError.detectionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRectangleObservation],
                      let observation = observations.first else {
                    self.logger.info("No rectangle detected")
                    continuation.resume(returning: nil)
                    return
                }

                let rect = DetectedRectangle(
                    topLeft: observation.topLeft,
                    topRight: observation.topRight,
                    bottomLeft: observation.bottomLeft,
                    bottomRight: observation.bottomRight,
                    confidence: observation.confidence
                )

                self.logger.info("Rectangle detected with confidence: \(observation.confidence)")
                continuation.resume(returning: rect)
            }

            // 名刺のアスペクト比に近い矩形を検出
            request.minimumAspectRatio = 0.4
            request.maximumAspectRatio = 0.8
            request.minimumSize = 0.1
            request.minimumConfidence = 0.5
            request.maximumObservations = 1

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                self.logger.error("Rectangle detection handler error: \(error.localizedDescription)")
                continuation.resume(throwing: ImageProcessorError.detectionFailed(error))
            }
        }
    }

    /// 検出された矩形に基づいて画像をクロップ・補正
    /// - Parameters:
    ///   - image: 入力画像
    ///   - rectangle: 検出された矩形
    /// - Returns: クロップ・補正された画像
    func cropAndCorrect(image: UIImage, rectangle: DetectedRectangle) async throws -> UIImage {
        guard let ciImage = CIImage(image: image) else {
            throw ImageProcessorError.invalidImage
        }

        let imageSize = ciImage.extent.size

        // 正規化座標を実際の座標に変換
        let topLeft = CGPoint(
            x: rectangle.topLeft.x * imageSize.width,
            y: rectangle.topLeft.y * imageSize.height
        )
        let topRight = CGPoint(
            x: rectangle.topRight.x * imageSize.width,
            y: rectangle.topRight.y * imageSize.height
        )
        let bottomLeft = CGPoint(
            x: rectangle.bottomLeft.x * imageSize.width,
            y: rectangle.bottomLeft.y * imageSize.height
        )
        let bottomRight = CGPoint(
            x: rectangle.bottomRight.x * imageSize.width,
            y: rectangle.bottomRight.y * imageSize.height
        )

        // 透視変換フィルタを適用
        guard let perspectiveFilter = CIFilter(name: "CIPerspectiveCorrection") else {
            throw ImageProcessorError.filterNotAvailable
        }

        perspectiveFilter.setValue(ciImage, forKey: kCIInputImageKey)
        perspectiveFilter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        perspectiveFilter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        perspectiveFilter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        perspectiveFilter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

        guard let outputImage = perspectiveFilter.outputImage else {
            throw ImageProcessorError.correctionFailed
        }

        // CIImageをUIImageに変換
        guard let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            throw ImageProcessorError.correctionFailed
        }

        logger.info("Image cropped and corrected successfully")
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// 自動検出してクロップ・補正（ワンステップ）
    /// - Parameter image: 入力画像
    /// - Returns: クロップ・補正された画像（矩形が検出されない場合は元画像）
    func autoCropAndCorrect(image: UIImage) async throws -> UIImage {
        if let rectangle = try await detectRectangle(in: image) {
            return try await cropAndCorrect(image: image, rectangle: rectangle)
        } else {
            logger.info("No rectangle detected, returning original image")
            return image
        }
    }

    /// 画像を指定サイズにリサイズ（アスペクト比を維持）
    /// - Parameters:
    ///   - image: 入力画像
    ///   - maxSize: 最大サイズ
    /// - Returns: リサイズされた画像
    func resize(image: UIImage, maxSize: CGSize) -> UIImage {
        let aspectRatio = image.size.width / image.size.height
        var newSize: CGSize

        if aspectRatio > 1 {
            // 横長
            newSize = CGSize(
                width: min(image.size.width, maxSize.width),
                height: min(image.size.width, maxSize.width) / aspectRatio
            )
        } else {
            // 縦長または正方形
            newSize = CGSize(
                width: min(image.size.height, maxSize.height) * aspectRatio,
                height: min(image.size.height, maxSize.height)
            )
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized
    }

    /// 画像の向きを正規化（EXIF orientationを適用）
    /// - Parameter image: 入力画像
    /// - Returns: 正規化された画像
    func normalizeOrientation(image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else {
            return image
        }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? image
    }

    /// 画像の向きを正規化（同期版、非actorコンテキストから呼び出し可能）
    /// - Parameter image: 入力画像
    /// - Returns: 正規化された画像
    nonisolated func normalizeOrientationSync(image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else {
            return image
        }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? image
    }

    // MARK: - Manual Rotation

    /// 画像を時計回りに90度回転（手動回転用）
    /// - Parameter image: 入力画像
    /// - Returns: 回転された画像
    func rotateClockwise90(image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let rotatedSize = CGSize(width: image.size.height, height: image.size.width)

        let renderer = UIGraphicsImageRenderer(size: rotatedSize)
        let rotatedImage = renderer.image { context in
            let ctx = context.cgContext

            // 中心に移動して90度時計回りに回転
            ctx.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            ctx.rotate(by: .pi / 2)

            // Y軸反転を補正して描画
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cgImage, in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
        }

        return rotatedImage
    }

    /// 画像を時計回りに90度回転（同期版、非actorコンテキストから呼び出し可能）
    /// - Parameter image: 入力画像
    /// - Returns: 回転された画像
    nonisolated func rotateClockwise90Sync(image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let rotatedSize = CGSize(width: image.size.height, height: image.size.width)

        let renderer = UIGraphicsImageRenderer(size: rotatedSize)
        let rotatedImage = renderer.image { context in
            let ctx = context.cgContext

            // 中心に移動して90度時計回りに回転
            ctx.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            ctx.rotate(by: .pi / 2)

            // Y軸反転を補正して描画
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cgImage, in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
        }

        return rotatedImage
    }

    // MARK: - Face Cropping

    /// 顔写真用にクロップ
    /// - Parameters:
    ///   - image: 入力画像
    ///   - faceRect: 顔の矩形（正規化座標）
    ///   - padding: 顔の周りの余白（比率）
    /// - Returns: クロップされた顔画像
    func cropFace(image: UIImage, faceRect: CGRect, padding: CGFloat = 0.3) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // 正規化座標を実際の座標に変換（Y座標は反転）
        let x = faceRect.origin.x * imageWidth
        let y = (1 - faceRect.origin.y - faceRect.height) * imageHeight
        let width = faceRect.width * imageWidth
        let height = faceRect.height * imageHeight

        // パディングを追加
        let paddingX = width * padding
        let paddingY = height * padding

        var cropRect = CGRect(
            x: max(0, x - paddingX),
            y: max(0, y - paddingY),
            width: min(imageWidth - x + paddingX, width + paddingX * 2),
            height: min(imageHeight - y + paddingY, height + paddingY * 2)
        )

        // 正方形にする
        let size = max(cropRect.width, cropRect.height)
        cropRect = CGRect(
            x: cropRect.midX - size / 2,
            y: cropRect.midY - size / 2,
            width: size,
            height: size
        )

        // 画像境界内に収める
        cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - DetectedRectangle

/// 検出された矩形の情報。
struct DetectedRectangle {
    /// 左上の座標（正規化座標 0.0〜1.0）
    let topLeft: CGPoint
    /// 右上の座標
    let topRight: CGPoint
    /// 左下の座標
    let bottomLeft: CGPoint
    /// 右下の座標
    let bottomRight: CGPoint
    /// 検出の信頼度
    let confidence: Float
}

// MARK: - ImageProcessorError

enum ImageProcessorError: LocalizedError {
    case invalidImage
    case detectionFailed(Error)
    case filterNotAvailable
    case correctionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return String(localized: "error.generic")
        case .detectionFailed(let error):
            return error.localizedDescription
        case .filterNotAvailable:
            return String(localized: "error.generic")
        case .correctionFailed:
            return String(localized: "error.generic")
        }
    }
}
