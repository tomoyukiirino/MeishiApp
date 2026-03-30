import Foundation
import SwiftData

// MARK: - BusinessCard（名刺）— Personに属する証跡

/// 名刺データ。Personに紐づく1枚の名刺を表す。
/// 同じ人が転職や異動で名刺が変わった場合、新しいBusinessCardがPersonに追加される。
@Model
final class BusinessCard {
    // MARK: - Properties

    /// 一意識別子
    var id: UUID

    /// 所属するPerson
    var person: Person?

    /// 名刺表面画像のファイルパス（必須）
    var frontImagePath: String

    /// 名刺裏面画像のファイルパス（オプション）
    var backImagePath: String?

    /// この名刺の会社名
    var company: String?

    /// 部署
    var department: String?

    /// 役職
    var title: String?

    /// 電話番号（複数可）
    var phoneNumbers: [String]

    /// メールアドレス（複数可）
    var emails: [String]

    /// 住所
    var address: String?

    /// Webサイト
    var website: String?

    /// 表面OCR生テキスト
    var ocrTextFront: String?

    /// 裏面OCR生テキスト
    var ocrTextBack: String?

    /// この名刺を受け取った日
    var acquiredAt: Date

    /// 作成日時
    var createdAt: Date

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        person: Person? = nil,
        frontImagePath: String,
        backImagePath: String? = nil,
        company: String? = nil,
        department: String? = nil,
        title: String? = nil,
        phoneNumbers: [String] = [],
        emails: [String] = [],
        address: String? = nil,
        website: String? = nil,
        ocrTextFront: String? = nil,
        ocrTextBack: String? = nil,
        acquiredAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.person = person
        self.frontImagePath = frontImagePath
        self.backImagePath = backImagePath
        self.company = company
        self.department = department
        self.title = title
        self.phoneNumbers = phoneNumbers
        self.emails = emails
        self.address = address
        self.website = website
        self.ocrTextFront = ocrTextFront
        self.ocrTextBack = ocrTextBack
        self.acquiredAt = acquiredAt
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    /// 裏面画像があるか
    var hasBackImage: Bool {
        backImagePath != nil && !backImagePath!.isEmpty
    }

    /// OCRテキスト全体（表面＋裏面）
    var fullOCRText: String {
        var text = ocrTextFront ?? ""
        if let backText = ocrTextBack, !backText.isEmpty {
            if !text.isEmpty {
                text += "\n"
            }
            text += backText
        }
        return text
    }

    /// 主要な電話番号（最初の1つ）
    var primaryPhoneNumber: String? {
        phoneNumbers.first
    }

    /// 主要なメールアドレス（最初の1つ）
    var primaryEmail: String? {
        emails.first
    }

    /// 会社名と部署を結合した文字列
    var companyAndDepartment: String? {
        switch (company, department) {
        case let (company?, department?):
            return "\(company) \(department)"
        case let (company?, nil):
            return company
        case let (nil, department?):
            return department
        default:
            return nil
        }
    }

    /// 表示用の取得日文字列
    var acquiredAtFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        return formatter.string(from: acquiredAt)
    }

    // MARK: - Methods

    /// 電話番号を追加（重複チェック付き）
    func addPhoneNumber(_ number: String) {
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !phoneNumbers.contains(trimmed) else { return }
        phoneNumbers.append(trimmed)
    }

    /// メールアドレスを追加（重複チェック付き）
    func addEmail(_ email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, !emails.contains(trimmed) else { return }
        emails.append(trimmed)
    }
}

// MARK: - Equatable

extension BusinessCard: Equatable {
    static func == (lhs: BusinessCard, rhs: BusinessCard) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension BusinessCard: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
