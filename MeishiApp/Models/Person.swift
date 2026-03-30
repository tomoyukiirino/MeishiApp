import Foundation
import SwiftData

// MARK: - Person（人）— 中心エンティティ

/// アプリの中心となるエンティティ。名刺は「人」に属する証跡として管理される。
/// 同一人物が転職などで名刺が変わっても、Personに新しいBusinessCardが追加されるだけで、
/// 人の同一性は保たれる。
@Model
final class Person {
    // MARK: - Properties

    /// 一意識別子
    var id: UUID

    /// 氏名（必須）
    var name: String

    /// ふりがな
    var nameReading: String?

    /// 現在の会社名（最新の名刺から自動更新）
    var primaryCompany: String?

    /// 現在の役職（最新の名刺から自動更新）
    var primaryTitle: String?

    /// この人についてのメモ
    var memo: String?

    /// 顔写真のファイルパス（Phase 2で使用）
    var facePhotoPath: String?

    /// メイン名刺のID（この名刺の情報がprimaryCompany/primaryTitleに使用される）
    var primaryCardId: UUID?

    // Phase 3で追加予定
    // var faceEmbedding: [Float]?

    /// この人の名刺一覧（1対多、cascade削除）
    @Relationship(deleteRule: .cascade, inverse: \BusinessCard.person)
    var businessCards: [BusinessCard] = []

    /// この人との出会いの記録一覧（1対多、cascade削除）
    @Relationship(deleteRule: .cascade, inverse: \Encounter.person)
    var encounters: [Encounter] = []

    /// タグ（多対多）
    @Relationship(inverse: \Tag.persons)
    var tags: [Tag] = []

    /// 作成日時
    var createdAt: Date

    /// 更新日時
    var updatedAt: Date

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        nameReading: String? = nil,
        primaryCompany: String? = nil,
        primaryTitle: String? = nil,
        memo: String? = nil,
        facePhotoPath: String? = nil,
        primaryCardId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.nameReading = nameReading
        self.primaryCompany = primaryCompany
        self.primaryTitle = primaryTitle
        self.memo = memo
        self.facePhotoPath = facePhotoPath
        self.primaryCardId = primaryCardId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed Properties

    /// メイン名刺を取得（primaryCardIdで指定された名刺、なければ最新の名刺）
    var primaryBusinessCard: BusinessCard? {
        if let primaryCardId = primaryCardId,
           let primaryCard = businessCards.first(where: { $0.id == primaryCardId }) {
            return primaryCard
        }
        // フォールバック: 最新の名刺
        return businessCards.sorted { $0.acquiredAt > $1.acquiredAt }.first
    }

    /// 最新の名刺を取得
    var latestBusinessCard: BusinessCard? {
        businessCards.sorted { $0.acquiredAt > $1.acquiredAt }.first
    }

    /// 名刺の枚数
    var businessCardCount: Int {
        businessCards.count
    }

    /// 出会いの記録数
    var encounterCount: Int {
        encounters.count
    }

    /// 顔写真が登録されているか
    var hasFacePhoto: Bool {
        facePhotoPath != nil && !facePhotoPath!.isEmpty
    }

    /// イニシャル（顔写真がない場合の代替表示用）
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            // 姓名がスペースで区切られている場合
            let firstInitial = components[0].prefix(1)
            let lastInitial = components[1].prefix(1)
            return String(firstInitial + lastInitial).uppercased()
        } else {
            // 日本語名など、スペースがない場合は先頭2文字
            return String(name.prefix(2))
        }
    }

    // MARK: - Methods

    /// メイン名刺の情報でprimaryCompanyとprimaryTitleを更新
    func updatePrimaryInfo() {
        guard let primary = primaryBusinessCard else {
            // 名刺がない場合はクリア
            primaryCompany = nil
            primaryTitle = nil
            primaryCardId = nil
            updatedAt = Date()
            return
        }
        primaryCompany = primary.company
        primaryTitle = primary.title
        updatedAt = Date()
    }

    /// メイン名刺を設定
    func setPrimaryCard(_ card: BusinessCard) {
        guard businessCards.contains(where: { $0.id == card.id }) else { return }
        primaryCardId = card.id
        updatePrimaryInfo()
    }

    /// 指定された名刺がメイン名刺かどうか
    func isPrimaryCard(_ card: BusinessCard) -> Bool {
        if let primaryCardId = primaryCardId {
            return card.id == primaryCardId
        }
        // primaryCardIdが設定されていない場合、最新の名刺がメイン
        return card.id == latestBusinessCard?.id
    }

    /// タグを追加
    func addTag(_ tag: Tag) {
        if !tags.contains(where: { $0.id == tag.id }) {
            tags.append(tag)
            updatedAt = Date()
        }
    }

    /// タグを削除
    func removeTag(_ tag: Tag) {
        tags.removeAll { $0.id == tag.id }
        updatedAt = Date()
    }
}

// MARK: - Equatable

extension Person: Equatable {
    static func == (lhs: Person, rhs: Person) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension Person: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
