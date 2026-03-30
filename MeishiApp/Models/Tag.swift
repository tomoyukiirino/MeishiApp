import Foundation
import SwiftData

// MARK: - Tag（タグ）

/// タグ。Personに対して自由に付与できる分類ラベル。
/// 「学会関係」「外科」「税理士さん」など、ユーザーの整理方法に合わせて使用。
@Model
final class Tag {
    // MARK: - Properties

    /// 一意識別子
    var id: UUID

    /// タグ名
    var name: String

    /// タグの色名（blue, green, orange, red, purple, pink, yellow, gray）
    var color: String

    /// このタグが付与されたPerson一覧（多対多）
    var persons: [Person] = []

    /// 作成日時
    var createdAt: Date

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        color: String = "blue",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    /// このタグが付与されたPersonの数
    var personCount: Int {
        persons.count
    }
}

// MARK: - Equatable

extension Tag: Equatable {
    static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension Tag: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
