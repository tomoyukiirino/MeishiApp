import Foundation
import Contacts
import UniformTypeIdentifiers
import os.log

// MARK: - ExportService

/// CSV/vCardエクスポートサービス。
actor ExportService {
    // MARK: - Types

    enum ExportFormat {
        case csv
        case vcard

        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .vcard: return "vcf"
            }
        }

        var mimeType: String {
            switch self {
            case .csv: return "text/csv"
            case .vcard: return "text/vcard"
            }
        }

        var utType: UTType {
            switch self {
            case .csv: return .commaSeparatedText
            case .vcard: return .vCard
            }
        }
    }

    // MARK: - Singleton

    static let shared = ExportService()

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "ExportService")

    // MARK: - Initialization

    private init() {}

    // MARK: - CSV Export

    /// PersonリストをCSV形式でエクスポート
    /// - Parameter persons: エクスポートするPersonのリスト
    /// - Returns: CSVデータ
    func exportToCSV(_ persons: [Person]) -> Data {
        var csvString = ""

        // BOM（Excel対応）
        csvString = "\u{FEFF}"

        // ヘッダー行
        let headers = [
            "氏名", "ふりがな", "会社名", "部署", "役職",
            "電話番号", "メールアドレス", "住所", "Webサイト",
            "メモ", "タグ", "登録日"
        ]
        csvString += headers.joined(separator: ",") + "\n"

        // データ行
        for person in persons {
            let latestCard = person.latestBusinessCard

            let row = [
                escapeCSV(person.name),
                escapeCSV(person.nameReading ?? ""),
                escapeCSV(latestCard?.company ?? ""),
                escapeCSV(latestCard?.department ?? ""),
                escapeCSV(latestCard?.title ?? ""),
                escapeCSV(latestCard?.phoneNumbers.joined(separator: "; ") ?? ""),
                escapeCSV(latestCard?.emails.joined(separator: "; ") ?? ""),
                escapeCSV(latestCard?.address ?? ""),
                escapeCSV(latestCard?.website ?? ""),
                escapeCSV(person.memo ?? ""),
                escapeCSV(person.tags.map { $0.name }.joined(separator: "; ")),
                escapeCSV(formatDate(person.createdAt))
            ]

            csvString += row.joined(separator: ",") + "\n"
        }

        logger.info("Exported \(persons.count) persons to CSV")
        return csvString.data(using: .utf8) ?? Data()
    }

    /// CSV用にエスケープ
    private func escapeCSV(_ value: String) -> String {
        var escaped = value
        // ダブルクォートをエスケープ
        escaped = escaped.replacingOccurrences(of: "\"", with: "\"\"")
        // カンマ、改行、ダブルクォートが含まれる場合はダブルクォートで囲む
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            escaped = "\"\(escaped)\""
        }
        return escaped
    }

    // MARK: - vCard Export

    /// PersonリストをvCard形式でエクスポート
    /// - Parameter persons: エクスポートするPersonのリスト
    /// - Returns: vCardデータ
    func exportToVCard(_ persons: [Person]) throws -> Data {
        var contacts: [CNContact] = []

        for person in persons {
            let contact = createContact(from: person)
            contacts.append(contact)
        }

        do {
            let vCardData = try CNContactVCardSerialization.data(with: contacts)
            logger.info("Exported \(persons.count) persons to vCard")
            return vCardData
        } catch {
            logger.error("Failed to serialize vCard: \(error.localizedDescription)")
            throw ExportError.vCardSerializationFailed(error)
        }
    }

    /// PersonからCNContactを生成（vCard用）
    private func createContact(from person: Person) -> CNContact {
        let contact = CNMutableContact()

        // 氏名
        let nameComponents = person.name.split(separator: " ", maxSplits: 1)
        if nameComponents.count >= 2 {
            contact.familyName = String(nameComponents[0])
            contact.givenName = String(nameComponents[1])
        } else {
            contact.familyName = person.name
        }

        // ふりがな
        if let reading = person.nameReading {
            let readingComponents = reading.split(separator: " ", maxSplits: 1)
            if readingComponents.count >= 2 {
                contact.phoneticFamilyName = String(readingComponents[0])
                contact.phoneticGivenName = String(readingComponents[1])
            } else {
                contact.phoneticFamilyName = reading
            }
        }

        // 最新の名刺から情報を取得
        if let latestCard = person.latestBusinessCard {
            if let company = latestCard.company {
                contact.organizationName = company
            }

            if let department = latestCard.department {
                contact.departmentName = department
            }

            if let title = latestCard.title {
                contact.jobTitle = title
            }

            contact.phoneNumbers = latestCard.phoneNumbers.map { number in
                CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: number))
            }

            contact.emailAddresses = latestCard.emails.map { email in
                CNLabeledValue(label: CNLabelWork, value: email as NSString)
            }

            if let addressString = latestCard.address {
                let postalAddress = CNMutablePostalAddress()
                postalAddress.street = addressString
                contact.postalAddresses = [
                    CNLabeledValue(label: CNLabelWork, value: postalAddress)
                ]
            }

            if let website = latestCard.website {
                contact.urlAddresses = [
                    CNLabeledValue(label: CNLabelWork, value: website as NSString)
                ]
            }
        }

        if let memo = person.memo {
            contact.note = memo
        }

        return contact
    }

    // MARK: - File Generation

    /// エクスポート用の一時ファイルを生成
    /// - Parameters:
    ///   - persons: エクスポートするPersonのリスト
    ///   - format: エクスポート形式
    /// - Returns: 一時ファイルのURL
    func generateExportFile(_ persons: [Person], format: ExportFormat) async throws -> URL {
        let data: Data

        switch format {
        case .csv:
            data = exportToCSV(persons)
        case .vcard:
            data = try exportToVCard(persons)
        }

        // 一時ファイルを作成
        let fileName = generateFileName(format: format)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: tempURL)
            logger.info("Export file created: \(tempURL.lastPathComponent)")
            return tempURL
        } catch {
            logger.error("Failed to write export file: \(error.localizedDescription)")
            throw ExportError.fileWriteFailed(error)
        }
    }

    /// ファイル名を生成
    private func generateFileName(format: ExportFormat) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        return "meishi_export_\(dateString).\(format.fileExtension)"
    }

    // MARK: - Utility

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
}

// MARK: - ExportError

enum ExportError: LocalizedError {
    case vCardSerializationFailed(Error)
    case fileWriteFailed(Error)

    var errorDescription: String? {
        switch self {
        case .vCardSerializationFailed:
            return String(localized: "export.failed")
        case .fileWriteFailed:
            return String(localized: "export.failed")
        }
    }
}

// MARK: - ExportView

import SwiftUI

/// エクスポート画面。
struct ExportView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let persons: [Person]

    @State private var selectedFormat: ExportService.ExportFormat = .csv
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var showingShareSheet = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("エクスポート対象")) {
                    LabeledContent("人数") {
                        Text("\(persons.count)人")
                    }
                }

                Section(header: Text("形式を選択")) {
                    Picker("形式", selection: $selectedFormat) {
                        Text(String(localized: "export.csv")).tag(ExportService.ExportFormat.csv)
                        Text(String(localized: "export.vcard")).tag(ExportService.ExportFormat.vcard)
                    }
                    .pickerStyle(.segmented)

                    switch selectedFormat {
                    case .csv:
                        Text("カンマ区切りファイル。Excelやスプレッドシートで開けます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .vcard:
                        Text("連絡先の標準形式。他のアプリやデバイスに取り込めます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task {
                            await exportData()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(String(localized: "export.title"))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isExporting || persons.isEmpty)
                }
            }
            .navigationTitle(String(localized: "export.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    // MARK: - Methods

    private func exportData() async {
        isExporting = true
        errorMessage = nil

        do {
            let url = try await ExportService.shared.generateExportFile(persons, format: selectedFormat)
            exportURL = url
            showingShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isExporting = false
    }
}

// MARK: - ShareSheet

/// UIActivityViewControllerのSwiftUIラッパー。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    ExportView(persons: [
        Person(name: "山田太郎", primaryCompany: "株式会社サンプル"),
        Person(name: "鈴木花子", primaryCompany: "テスト株式会社")
    ])
}
