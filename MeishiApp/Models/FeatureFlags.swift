import Foundation

// MARK: - FeatureFlags（フィーチャーフラグ）

/// フィーチャーフラグ。課金状態に応じて機能の有効/無効を制御する。
/// 開発段階では全てtrue。商品化時にサブスクリプション状態と連携させる。
@Observable
final class FeatureFlags {
    // MARK: - Singleton

    static let shared = FeatureFlags()

    // MARK: - Feature Flags

    /// Claude API構造化（有料機能 - APIコストが発生）
    var isAIStructuringEnabled: Bool = true

    /// 顔写真の紐づけ（Phase 2）
    var isFacePhotoEnabled: Bool = true

    /// 同一人物検索（Phase 3）
    var isFaceSearchEnabled: Bool = true

    /// 写真から逆引き検索（Phase 3）
    var isReverseFaceLookupEnabled: Bool = true

    /// CSV/vCardエクスポート
    var isExportEnabled: Bool = true

    /// クラウドバックアップ（iCloud Drive等）
    var isCloudBackupEnabled: Bool = true

    /// 高度なタグ機能
    var isAdvancedTaggingEnabled: Bool = true

    // MARK: - Initialization

    private init() {
        // 開発中は全機能有効
        #if DEBUG
        enableAllFeatures()
        #endif
    }

    // MARK: - Methods

    /// サブスクリプション状態に基づいてフラグを更新
    /// - Parameter isSubscribed: サブスクリプションが有効かどうか
    func updateFromSubscription(_ isSubscribed: Bool) {
        // TODO: Phase 4で実装 - どの機能を有料にするかは後日決定
        // 現時点では全機能有効のまま
        if isSubscribed {
            enableAllFeatures()
        } else {
            // 無料版での制限（後日決定）
            // 例: isAIStructuringEnabled = false
        }
    }

    /// 全機能を有効化（開発・テスト用）
    func enableAllFeatures() {
        isAIStructuringEnabled = true
        isFacePhotoEnabled = true
        isFaceSearchEnabled = true
        isReverseFaceLookupEnabled = true
        isExportEnabled = true
        isCloudBackupEnabled = true
        isAdvancedTaggingEnabled = true
    }

    /// 機能が利用可能かチェックし、利用不可の場合はプレミアム購入を促す
    /// - Parameter feature: チェックする機能のフラグ
    /// - Returns: 機能が有効かどうか
    func checkFeatureAvailability(_ feature: Feature) -> Bool {
        switch feature {
        case .aiStructuring:
            return isAIStructuringEnabled
        case .facePhoto:
            return isFacePhotoEnabled
        case .faceSearch:
            return isFaceSearchEnabled
        case .reverseFaceLookup:
            return isReverseFaceLookupEnabled
        case .export:
            return isExportEnabled
        case .cloudBackup:
            return isCloudBackupEnabled
        case .advancedTagging:
            return isAdvancedTaggingEnabled
        }
    }

    // MARK: - Feature Enum

    enum Feature {
        case aiStructuring
        case facePhoto
        case faceSearch
        case reverseFaceLookup
        case export
        case cloudBackup
        case advancedTagging

        var localizedName: String {
            switch self {
            case .aiStructuring:
                return String(localized: "settings.ai")
            case .facePhoto:
                return String(localized: "face.add")
            case .faceSearch:
                return String(localized: "person.detail.findPhotos")
            case .reverseFaceLookup:
                return String(localized: "face.searchFromPhoto")
            case .export:
                return String(localized: "export.title")
            case .cloudBackup:
                return String(localized: "backup.icloud")
            case .advancedTagging:
                return String(localized: "tag.add")
            }
        }
    }
}
