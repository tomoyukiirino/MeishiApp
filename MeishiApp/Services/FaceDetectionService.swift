import Foundation
import Vision
import UIKit
import os.log

// MARK: - FaceDetectionService

/// Apple Vision Frameworkを使用した顔検出サービス。
/// 写真から顔を検出し、矩形情報を返す。
actor FaceDetectionService {
    // MARK: - Singleton

    static let shared = FaceDetectionService()

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "FaceDetection")

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// 画像から顔を検出
    /// - Parameter image: 入力画像
    /// - Returns: 検出された顔の情報リスト
    func detectFaces(in image: UIImage) async throws -> [DetectedFace] {
        guard let cgImage = image.cgImage else {
            throw FaceDetectionError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            // continuationが一度だけresumeされることを保証するフラグ
            var hasResumed = false

            let request = VNDetectFaceRectanglesRequest { request, error in
                guard !hasResumed else { return }
                hasResumed = true

                if let error = error {
                    self.logger.error("Face detection error: \(error.localizedDescription)")
                    continuation.resume(throwing: FaceDetectionError.detectionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let faces = observations.map { observation in
                    DetectedFace(
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence
                    )
                }

                self.logger.info("Detected \(faces.count) faces")
                continuation.resume(returning: faces)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                guard !hasResumed else { return }
                hasResumed = true
                self.logger.error("Face detection handler error: \(error.localizedDescription)")
                continuation.resume(throwing: FaceDetectionError.detectionFailed(error))
            }
        }
    }

    /// 顔の詳細情報（ランドマーク含む）を検出
    /// - Parameter image: 入力画像
    /// - Returns: 詳細な顔情報リスト
    func detectFacesWithLandmarks(in image: UIImage) async throws -> [DetailedFace] {
        guard let cgImage = image.cgImage else {
            throw FaceDetectionError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            // continuationが一度だけresumeされることを保証するフラグ
            var hasResumed = false

            let request = VNDetectFaceLandmarksRequest { request, error in
                guard !hasResumed else { return }
                hasResumed = true

                if let error = error {
                    self.logger.error("Face landmarks detection error: \(error.localizedDescription)")
                    continuation.resume(throwing: FaceDetectionError.detectionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let faces = observations.map { observation in
                    DetailedFace(
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence,
                        landmarks: observation.landmarks,
                        roll: observation.roll?.doubleValue,
                        yaw: observation.yaw?.doubleValue,
                        pitch: observation.pitch?.doubleValue
                    )
                }

                self.logger.info("Detected \(faces.count) faces with landmarks")
                continuation.resume(returning: faces)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                guard !hasResumed else { return }
                hasResumed = true
                self.logger.error("Face landmarks detection handler error: \(error.localizedDescription)")
                continuation.resume(throwing: FaceDetectionError.detectionFailed(error))
            }
        }
    }

    /// 画像から顔をクロップ
    /// - Parameters:
    ///   - image: 入力画像
    ///   - face: 検出された顔情報
    ///   - padding: 顔の周りの余白（比率）
    /// - Returns: クロップされた顔画像
    func cropFace(from image: UIImage, face: DetectedFace, padding: CGFloat = 0.3) -> UIImage? {
        // 同期的にクロップを実行
        guard let cgImage = image.cgImage else { return nil }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Vision座標系からUIKit座標系に変換
        let boundingBox = face.boundingBox
        let x = boundingBox.origin.x * imageWidth
        let y = (1 - boundingBox.origin.y - boundingBox.height) * imageHeight
        let width = boundingBox.width * imageWidth
        let height = boundingBox.height * imageHeight

        // パディングを追加
        let paddingX = width * padding
        let paddingY = height * padding

        let cropRect = CGRect(
            x: max(0, x - paddingX),
            y: max(0, y - paddingY),
            width: min(imageWidth - x + paddingX, width + paddingX * 2),
            height: min(imageHeight - y + paddingY, height + paddingY * 2)
        )

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// 顔をクロップ（同期版、内部使用）
    private func cropFaceSync(from image: UIImage, boundingBox: CGRect, padding: CGFloat) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Vision座標系（左下原点、正規化）からUIKit座標系（左上原点、ピクセル）に変換
        let x = boundingBox.origin.x * imageWidth
        let y = (1 - boundingBox.origin.y - boundingBox.height) * imageHeight
        let width = boundingBox.width * imageWidth
        let height = boundingBox.height * imageHeight

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
            x: max(0, cropRect.midX - size / 2),
            y: max(0, cropRect.midY - size / 2),
            width: size,
            height: size
        )

        // 画像境界内に収める
        cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// 複数の顔をまとめてクロップ
    /// - Parameters:
    ///   - image: 入力画像
    ///   - faces: 検出された顔情報のリスト
    ///   - padding: 顔の周りの余白
    /// - Returns: クロップされた顔画像のリスト（顔情報とペア）
    func cropFaces(from image: UIImage, faces: [DetectedFace], padding: CGFloat = 0.3) async -> [(face: DetectedFace, image: UIImage)] {
        var results: [(DetectedFace, UIImage)] = []

        for face in faces {
            if let croppedImage = await cropFaceSync(from: image, boundingBox: face.boundingBox, padding: padding) {
                results.append((face, croppedImage))
            }
        }

        return results
    }

    /// 顔の品質スコアを計算（正面向き、十分なサイズなど）
    /// - Parameter face: 詳細な顔情報
    /// - Returns: 品質スコア（0.0〜1.0）
    func calculateQualityScore(face: DetailedFace) -> Double {
        var score: Double = 1.0

        // 顔のサイズ（小さすぎると減点）
        let areaScore = min(1.0, face.boundingBox.width * face.boundingBox.height * 10)
        score *= areaScore

        // 向き（正面に近いほど高スコア）
        if let yaw = face.yaw {
            let yawScore = 1.0 - min(1.0, abs(yaw) / Double.pi * 2)
            score *= yawScore
        }

        if let roll = face.roll {
            let rollScore = 1.0 - min(1.0, abs(roll) / Double.pi * 2)
            score *= rollScore
        }

        if let pitch = face.pitch {
            let pitchScore = 1.0 - min(1.0, abs(pitch) / Double.pi * 2)
            score *= pitchScore
        }

        // 検出の信頼度
        score *= Double(face.confidence)

        return score
    }
}

// MARK: - DetectedFace

/// 検出された顔の基本情報。
struct DetectedFace: Identifiable {
    let id = UUID()

    /// 顔の矩形（正規化座標 0.0〜1.0、左下原点）
    let boundingBox: CGRect

    /// 検出の信頼度
    let confidence: Float

    /// UIKit座標系での矩形を取得
    /// - Parameters:
    ///   - imageWidth: 画像の幅
    ///   - imageHeight: 画像の高さ
    /// - Returns: UIKit座標系での矩形
    func rectInImageCoordinates(imageWidth: CGFloat, imageHeight: CGFloat) -> CGRect {
        CGRect(
            x: boundingBox.origin.x * imageWidth,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageHeight,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        )
    }
}

// MARK: - DetailedFace

/// ランドマーク情報を含む詳細な顔情報。
struct DetailedFace: Identifiable {
    let id = UUID()

    /// 顔の矩形
    let boundingBox: CGRect

    /// 検出の信頼度
    let confidence: Float

    /// 顔のランドマーク（目、鼻、口など）
    let landmarks: VNFaceLandmarks2D?

    /// ロール角（首を傾げる方向の回転）
    let roll: Double?

    /// ヨー角（左右を向く回転）
    let yaw: Double?

    /// ピッチ角（上下を向く回転）
    let pitch: Double?

    /// 正面を向いているか（おおよそ）
    var isFacingFront: Bool {
        guard let yaw = yaw, let pitch = pitch else { return true }
        return abs(yaw) < 0.3 && abs(pitch) < 0.3
    }
}

// MARK: - FaceDetectionError

enum FaceDetectionError: LocalizedError {
    case invalidImage
    case detectionFailed(Error)
    case noFaceDetected

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return String(localized: "error.generic")
        case .detectionFailed(let error):
            return error.localizedDescription
        case .noFaceDetected:
            return String(localized: "face.noFaceDetected")
        }
    }
}
