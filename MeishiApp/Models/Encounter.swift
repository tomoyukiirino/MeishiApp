import Foundation
import SwiftData

// MARK: - Encounter（出会いの記録）— Personとの出会い

/// 出会いの記録。いつ・どこで・どのような状況で会ったかを記録する。
/// 名刺を受け取った出会いには、BusinessCardへの参照を持つ。
@Model
final class Encounter {
    // MARK: - Properties

    /// 一意識別子
    var id: UUID

    /// 出会った人
    var person: Person?

    /// イベント名（学会名、展示会名など）
    var eventName: String?

    /// 日時
    var date: Date?

    /// 場所
    var location: String?

    /// この出会いでのメモ（「日本酒が好きと言っていた」等）
    var memo: String?

    /// この出会いで受け取った名刺（オプション）
    @Relationship
    var businessCard: BusinessCard?

    /// 作成日時
    var createdAt: Date

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        person: Person? = nil,
        eventName: String? = nil,
        date: Date? = nil,
        location: String? = nil,
        memo: String? = nil,
        businessCard: BusinessCard? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.person = person
        self.eventName = eventName
        self.date = date
        self.location = location
        self.memo = memo
        self.businessCard = businessCard
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    /// 表示用の日付文字列
    var dateFormatted: String? {
        guard let date = date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    /// 表示用の日時文字列（時間含む）
    var dateTimeFormatted: String? {
        guard let date = date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    /// 出会いの概要文字列（一覧表示用）
    var summary: String {
        var parts: [String] = []

        if let eventName = eventName, !eventName.isEmpty {
            parts.append(eventName)
        }

        if let location = location, !location.isEmpty {
            parts.append(location)
        }

        if let dateFormatted = dateFormatted {
            parts.append(dateFormatted)
        }

        return parts.isEmpty ? String(localized: "encounter.add") : parts.joined(separator: " / ")
    }

    /// 名刺を受け取った出会いか
    var hasBusinessCard: Bool {
        businessCard != nil
    }
}

// MARK: - Equatable

extension Encounter: Equatable {
    static func == (lhs: Encounter, rhs: Encounter) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension Encounter: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
