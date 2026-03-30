import Foundation
import LocalAuthentication
import os.log

// MARK: - AuthenticationService

/// 生体認証（Face ID / Touch ID）を管理するサービス。
/// アプリ起動時とバックグラウンドからの復帰時に認証を要求する。
@Observable
final class AuthenticationService {
    // MARK: - Singleton

    static let shared = AuthenticationService()

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "Authentication")

    /// 認証が有効化されているか（ユーザー設定）
    var isAuthenticationEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "isAuthenticationEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isAuthenticationEnabled")
        }
    }

    /// アプリがロックされているか
    private(set) var isLocked: Bool = true

    /// 利用可能な生体認証タイプ
    private(set) var biometryType: LABiometryType = .none

    // MARK: - Initialization

    private init() {
        checkBiometryType()
        // 認証が無効の場合はロック解除状態で開始
        if !isAuthenticationEnabled {
            isLocked = false
        }
    }

    // MARK: - Public Methods

    /// 生体認証が利用可能かチェック
    func isBiometryAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if let error = error {
            logger.warning("Biometry not available: \(error.localizedDescription)")
        }

        return canEvaluate
    }

    /// デバイス認証（生体認証 + パスコードフォールバック）が利用可能かチェック
    func isDeviceAuthenticationAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)

        if let error = error {
            logger.warning("Device authentication not available: \(error.localizedDescription)")
        }

        return canEvaluate
    }

    /// 利用可能な生体認証タイプを確認
    func checkBiometryType() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometryType = context.biometryType
        } else {
            biometryType = .none
        }

        logger.info("Biometry type: \(String(describing: self.biometryType))")
    }

    /// 認証を実行
    /// - Returns: 認証成功の場合true
    @MainActor
    func authenticate() async -> AuthenticationResult {
        // 認証が無効の場合は常に成功
        guard isAuthenticationEnabled else {
            isLocked = false
            return .success
        }

        // デバイス認証が利用できない場合
        guard isDeviceAuthenticationAvailable() else {
            logger.warning("Device authentication not available")
            isLocked = false
            return .notAvailable
        }

        let context = LAContext()
        context.localizedCancelTitle = String(localized: "common.cancel")
        context.localizedFallbackTitle = String(localized: "auth.passcode")

        let reason = String(localized: "auth.reason")

        do {
            // 生体認証 + パスコードフォールバック
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )

            if success {
                isLocked = false
                logger.info("Authentication successful")
                return .success
            } else {
                logger.warning("Authentication failed")
                return .failed
            }
        } catch let error as LAError {
            return handleLAError(error)
        } catch {
            logger.error("Authentication error: \(error.localizedDescription)")
            return .failed
        }
    }

    /// アプリをロック状態にする
    func lock() {
        guard isAuthenticationEnabled else { return }
        isLocked = true
        logger.info("App locked")
    }

    /// アプリのロックを解除（認証なしで直接解除）
    func unlock() {
        isLocked = false
        logger.info("App unlocked")
    }

    /// 認証設定を有効/無効にする
    /// - Parameter enabled: 有効にする場合true
    /// - Returns: 設定変更が成功したかどうか
    @MainActor
    func setAuthenticationEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            // 有効にする前に認証をテスト
            guard isDeviceAuthenticationAvailable() else {
                logger.warning("Cannot enable authentication: device authentication not available")
                return false
            }

            let context = LAContext()
            let reason = String(localized: "auth.reason")

            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason
                )

                if success {
                    isAuthenticationEnabled = true
                    isLocked = false
                    logger.info("Authentication enabled")
                    return true
                }
            } catch {
                logger.error("Failed to enable authentication: \(error.localizedDescription)")
                return false
            }
        } else {
            // 無効にする前に認証を要求
            let result = await authenticate()
            if result == .success {
                isAuthenticationEnabled = false
                isLocked = false
                logger.info("Authentication disabled")
                return true
            }
        }

        return false
    }

    // MARK: - Private Methods

    private func handleLAError(_ error: LAError) -> AuthenticationResult {
        switch error.code {
        case .userCancel:
            logger.info("Authentication cancelled by user")
            return .cancelled

        case .userFallback:
            logger.info("User chose fallback authentication")
            return .failed

        case .authenticationFailed:
            logger.warning("Authentication failed")
            return .failed

        case .biometryNotAvailable:
            logger.warning("Biometry not available")
            return .notAvailable

        case .biometryNotEnrolled:
            logger.warning("Biometry not enrolled")
            return .notAvailable

        case .biometryLockout:
            logger.warning("Biometry locked out")
            return .lockedOut

        case .passcodeNotSet:
            logger.warning("Passcode not set")
            return .notAvailable

        default:
            logger.error("Authentication error: \(error.localizedDescription)")
            return .failed
        }
    }

    // MARK: - Computed Properties

    /// 生体認証の表示名
    var biometryName: String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return String(localized: "auth.passcode")
        @unknown default:
            return String(localized: "auth.passcode")
        }
    }

    /// 設定画面で表示するロック設定のラベル
    var lockSettingLabel: String {
        switch biometryType {
        case .faceID:
            return String(localized: "settings.biometricLock.faceId")
        case .touchID:
            return String(localized: "settings.biometricLock.touchId")
        default:
            return String(localized: "settings.biometricLock")
        }
    }
}

// MARK: - AuthenticationResult

enum AuthenticationResult: Equatable {
    case success
    case failed
    case cancelled
    case notAvailable
    case lockedOut

    var localizedMessage: String {
        switch self {
        case .success:
            return ""
        case .failed:
            return String(localized: "auth.failed")
        case .cancelled:
            return String(localized: "auth.cancelled")
        case .notAvailable:
            return String(localized: "auth.notAvailable")
        case .lockedOut:
            return String(localized: "auth.failed")
        }
    }
}
