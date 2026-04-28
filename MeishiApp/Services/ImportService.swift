import Foundation
import SwiftData
import Contacts

// MARK: - Import Result Types

/// インポート結果
struct ImportResult {
    let totalCount: Int       // ファイル内の件数
    let importedCount: Int    // 新規インポートされた件数
    let duplicateCount: Int   // 重複として検出された件数
    let skippedCount: Int     // データ不足等でスキップされた件数
    let errors: [ImportError] // 個別のエラー
}

/// インポートエラー
struct ImportError: Identifiable {
    let id = UUID()
    let lineNumber: Int?      // CSVの行番号（vCardの場合はnil）
    let name: String?         // 該当する名前（特定できれば）
    let reason: String        // エラー理由
}

/// 重複処理の方法
enum DuplicateHandling {
    case skip       // スキップする
    case addCard    // 名刺として追加する
}

/// インポートプレビュー結果
struct ImportPreview {
    let totalCount: Int
    let duplicateCount: Int
    let entries: [ImportEntry]
}

/// インポートエントリ
struct ImportEntry: Identifiable {
    let id = UUID()
    let name: String
    let nameReading: String?
    let company: String?
    let department: String?
    let title: String?
    let phoneNumbers: [String]
    let emails: [String]
    let address: String?
    let websites: [String]
    let memo: String?
    var isDuplicate: Bool = false
    var duplicatePersonId: UUID? = nil
}

// MARK: - Import Service

/// CSV/vCardファイルのインポートを担当
final class ImportService {

    static let shared = ImportService()

    private init() {}

    // MARK: - CSV Import

    /// CSVファイルをプレビュー
    func previewCSV(from url: URL, modelContext: ModelContext) throws -> ImportPreview {
        let entries = try parseCSV(from: url)
        return createPreview(entries: entries, modelContext: modelContext)
    }

    /// CSVファイルからPersonとBusinessCardを作成
    func importCSV(
        from url: URL,
        modelContext: ModelContext,
        duplicateHandling: DuplicateHandling
    ) throws -> ImportResult {
        let entries = try parseCSV(from: url)
        return importEntries(entries, modelContext: modelContext, duplicateHandling: duplicateHandling)
    }

    // MARK: - vCard Import

    /// vCardファイルをプレビュー
    func previewVCard(from url: URL, modelContext: ModelContext) throws -> ImportPreview {
        let entries = try parseVCard(from: url)
        return createPreview(entries: entries, modelContext: modelContext)
    }

    /// vCard/VCFファイルからPersonとBusinessCardを作成
    func importVCard(
        from url: URL,
        modelContext: ModelContext,
        duplicateHandling: DuplicateHandling
    ) throws -> ImportResult {
        let entries = try parseVCard(from: url)
        return importEntries(entries, modelContext: modelContext, duplicateHandling: duplicateHandling)
    }

    // MARK: - CSV Parsing

    private func parseCSV(from url: URL) throws -> [ImportEntry] {
        // ファイルの読み込み
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportServiceError.fileAccessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: url)

        // UTF-8でデコード（BOM対応）
        var content: String
        if let utf8String = String(data: data, encoding: .utf8) {
            content = utf8String
        } else if let utf16String = String(data: data, encoding: .utf16) {
            content = utf16String
        } else if let shiftJISString = String(data: data, encoding: .shiftJIS) {
            content = shiftJISString
        } else {
            throw ImportServiceError.invalidEncoding
        }

        // BOMを除去
        if content.hasPrefix("\u{FEFF}") {
            content.removeFirst()
        }

        // 行に分割
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard lines.count >= 2 else {
            throw ImportServiceError.noData
        }

        // ヘッダー行をパース
        let headerLine = lines[0]
        let headers = parseCSVLine(headerLine)
        let columnMap = mapHeaders(headers)

        if columnMap.isEmpty {
            throw ImportServiceError.headerNotFound
        }

        // データ行をパース
        var entries: [ImportEntry] = []

        for i in 1..<lines.count {
            let line = lines[i]
            let values = parseCSVLine(line)

            if let entry = createEntryFromCSV(values: values, columnMap: columnMap) {
                entries.append(entry)
            }
        }

        return entries
    }

    /// CSVの1行をパース（ダブルクォート対応）
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var previousChar: Character?

        for char in line {
            if char == "\"" {
                if inQuotes && previousChar == "\"" {
                    // エスケープされたダブルクォート
                    current.append("\"")
                    previousChar = nil
                    continue
                }
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
            previousChar = char
        }

        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    /// ヘッダー名をフィールドにマッピング
    private func mapHeaders(_ headers: [String]) -> [Int: CSVField] {
        var map: [Int: CSVField] = [:]

        for (index, header) in headers.enumerated() {
            let normalized = header.lowercased().trimmingCharacters(in: .whitespaces)

            if let field = CSVField.fromHeader(normalized) {
                map[index] = field
            }
        }

        return map
    }

    /// CSV値からImportEntryを作成
    private func createEntryFromCSV(values: [String], columnMap: [Int: CSVField]) -> ImportEntry? {
        var name = ""
        var nameReading: String?
        var company: String?
        var department: String?
        var title: String?
        var phoneNumbers: [String] = []
        var emails: [String] = []
        var address: String?
        var websites: [String] = []
        var memo: String?

        for (index, field) in columnMap {
            guard index < values.count else { continue }
            let value = values[index].trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }

            switch field {
            case .name:
                name = value
            case .nameReading:
                nameReading = value
            case .company:
                company = value
            case .department:
                department = value
            case .title:
                title = value
            case .phone:
                phoneNumbers.append(contentsOf: splitMultipleValues(value))
            case .email:
                emails.append(contentsOf: splitMultipleValues(value))
            case .address:
                address = value
            case .website:
                websites.append(contentsOf: splitMultipleValues(value))
            case .memo:
                memo = value
            }
        }

        // 氏名または会社名が必須
        if name.isEmpty && (company?.isEmpty ?? true) {
            return nil
        }

        return ImportEntry(
            name: name,
            nameReading: nameReading,
            company: company,
            department: department,
            title: title,
            phoneNumbers: phoneNumbers,
            emails: emails,
            address: address,
            websites: websites,
            memo: memo
        )
    }

    /// セミコロン区切りの値を分割
    private func splitMultipleValues(_ value: String) -> [String] {
        return value.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - vCard Parsing

    private func parseVCard(from url: URL) throws -> [ImportEntry] {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportServiceError.fileAccessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: url)

        let contacts = try CNContactVCardSerialization.contacts(with: data)

        if contacts.isEmpty {
            throw ImportServiceError.noData
        }

        return contacts.compactMap { createEntryFromContact($0) }
    }

    /// CNContactからImportEntryを作成
    private func createEntryFromContact(_ contact: CNContact) -> ImportEntry? {
        let formatter = CNContactFormatter()
        formatter.style = .fullName

        let name = formatter.string(from: contact) ?? ""

        var nameReading: String?
        let phonetic = [contact.phoneticGivenName, contact.phoneticFamilyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !phonetic.isEmpty {
            nameReading = phonetic
        }

        let company = contact.organizationName.isEmpty ? nil : contact.organizationName
        let department = contact.departmentName.isEmpty ? nil : contact.departmentName
        let title = contact.jobTitle.isEmpty ? nil : contact.jobTitle

        let phoneNumbers = contact.phoneNumbers.map { $0.value.stringValue }
        let emails = contact.emailAddresses.map { $0.value as String }

        var address: String?
        if let postalAddress = contact.postalAddresses.first?.value {
            let addressFormatter = CNPostalAddressFormatter()
            address = addressFormatter.string(from: postalAddress)
        }

        let websites = contact.urlAddresses.map { $0.value as String }

        var memo: String?
        if !contact.note.isEmpty {
            memo = contact.note
        }

        // 氏名または会社名が必須
        if name.isEmpty && (company?.isEmpty ?? true) {
            return nil
        }

        return ImportEntry(
            name: name,
            nameReading: nameReading,
            company: company,
            department: department,
            title: title,
            phoneNumbers: phoneNumbers,
            emails: emails,
            address: address,
            websites: websites,
            memo: memo
        )
    }

    // MARK: - Preview & Import

    /// プレビューを作成
    private func createPreview(entries: [ImportEntry], modelContext: ModelContext) -> ImportPreview {
        var updatedEntries = entries
        var duplicateCount = 0

        // 既存のPersonを取得
        let descriptor = FetchDescriptor<Person>()
        let existingPersons = (try? modelContext.fetch(descriptor)) ?? []

        for i in 0..<updatedEntries.count {
            if let duplicate = findDuplicate(entry: updatedEntries[i], in: existingPersons) {
                updatedEntries[i].isDuplicate = true
                updatedEntries[i].duplicatePersonId = duplicate.id
                duplicateCount += 1
            }
        }

        return ImportPreview(
            totalCount: entries.count,
            duplicateCount: duplicateCount,
            entries: updatedEntries
        )
    }

    /// 重複を検出
    private func findDuplicate(entry: ImportEntry, in persons: [Person]) -> Person? {
        for person in persons {
            // 氏名 + 会社名の完全一致
            if !entry.name.isEmpty && entry.name == person.name {
                if let company = entry.company, company == person.primaryCompany {
                    return person
                }
            }

            // メールアドレスの一致
            for email in entry.emails {
                for card in person.businessCards {
                    if card.emails.contains(email) {
                        return person
                    }
                }
            }
        }

        return nil
    }

    /// エントリをインポート
    private func importEntries(
        _ entries: [ImportEntry],
        modelContext: ModelContext,
        duplicateHandling: DuplicateHandling
    ) -> ImportResult {
        var importedCount = 0
        var duplicateCount = 0
        let errors: [ImportError] = []

        // 既存のPersonを取得
        let descriptor = FetchDescriptor<Person>()
        let existingPersons = (try? modelContext.fetch(descriptor)) ?? []

        for entry in entries {
            // 重複チェック
            if let existingPerson = findDuplicate(entry: entry, in: existingPersons) {
                duplicateCount += 1

                switch duplicateHandling {
                case .skip:
                    continue
                case .addCard:
                    // 既存Personに名刺を追加
                    let card = createBusinessCard(from: entry)
                    existingPerson.businessCards.append(card)
                    importedCount += 1
                }
            } else {
                // 新規Person作成
                let person = createPerson(from: entry)
                modelContext.insert(person)
                importedCount += 1
            }
        }

        try? modelContext.save()

        return ImportResult(
            totalCount: entries.count,
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            skippedCount: duplicateHandling == .skip ? duplicateCount : 0,
            errors: errors
        )
    }

    /// ImportEntryからPersonを作成
    private func createPerson(from entry: ImportEntry) -> Person {
        let person = Person(
            name: entry.name,
            nameReading: entry.nameReading,
            primaryCompany: entry.company,
            primaryTitle: entry.title,
            memo: entry.memo
        )

        let card = createBusinessCard(from: entry)
        person.businessCards.append(card)

        return person
    }

    /// ImportEntryからBusinessCardを作成
    private func createBusinessCard(from entry: ImportEntry) -> BusinessCard {
        BusinessCard(
            frontImagePath: "",
            company: entry.company,
            department: entry.department,
            title: entry.title,
            phoneNumbers: entry.phoneNumbers,
            emails: entry.emails,
            address: entry.address,
            website: entry.websites.first,
            acquiredAt: Date()
        )
    }
}

// MARK: - CSV Field Mapping

private enum CSVField {
    case name
    case nameReading
    case company
    case department
    case title
    case phone
    case email
    case address
    case website
    case memo

    static func fromHeader(_ header: String) -> CSVField? {
        let nameHeaders = ["name", "氏名", "名前", "full name", "fullname", "display name"]
        let nameReadingHeaders = ["namereading", "ふりがな", "フリガナ", "reading", "phonetic", "name reading"]
        let companyHeaders = ["company", "会社名", "会社", "organization", "org", "所属"]
        let departmentHeaders = ["department", "部署", "dept"]
        let titleHeaders = ["title", "役職", "position", "job title", "jobtitle"]
        let phoneHeaders = ["phone", "電話番号", "電話", "tel", "telephone", "mobile", "携帯", "phone1", "phone2", "phone3"]
        let emailHeaders = ["email", "メールアドレス", "メール", "e-mail", "mail", "email1", "email2", "email3"]
        let addressHeaders = ["address", "住所", "所在地"]
        let websiteHeaders = ["website", "ウェブサイト", "url", "web", "ホームページ", "hp"]
        let memoHeaders = ["memo", "メモ", "note", "notes", "備考"]

        if nameHeaders.contains(header) { return .name }
        if nameReadingHeaders.contains(header) { return .nameReading }
        if companyHeaders.contains(header) { return .company }
        if departmentHeaders.contains(header) { return .department }
        if titleHeaders.contains(header) { return .title }
        if phoneHeaders.contains(where: { header.hasPrefix($0) }) { return .phone }
        if emailHeaders.contains(where: { header.hasPrefix($0) }) { return .email }
        if addressHeaders.contains(header) { return .address }
        if websiteHeaders.contains(header) { return .website }
        if memoHeaders.contains(header) { return .memo }

        return nil
    }
}

// MARK: - Errors

enum ImportServiceError: LocalizedError {
    case fileAccessDenied
    case invalidEncoding
    case invalidFormat
    case noData
    case headerNotFound

    var errorDescription: String? {
        switch self {
        case .fileAccessDenied:
            return String(localized: "import.error.fileAccessDenied")
        case .invalidEncoding:
            return String(localized: "import.error.invalidFormat")
        case .invalidFormat:
            return String(localized: "import.error.invalidFormat")
        case .noData:
            return String(localized: "import.error.noData")
        case .headerNotFound:
            return String(localized: "import.error.headerNotFound")
        }
    }
}
