import Foundation
import Contacts
import ContactsUI
import os.log

// MARK: - ContactService

/// iPhone連絡先への片方向エクスポートサービス。
/// 同期は行わない。連絡先側で修正してもアプリには反映されない（逆も同様）。
actor ContactService {
    // MARK: - Singleton

    static let shared = ContactService()

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "ContactService")
    private let contactStore = CNContactStore()

    // MARK: - Initialization

    private init() {}

    // MARK: - Authorization

    /// 連絡先へのアクセス権限状態を取得
    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    /// 連絡先へのアクセス権限をリクエスト
    func requestAuthorization() async -> Bool {
        do {
            return try await contactStore.requestAccess(for: .contacts)
        } catch {
            logger.error("Contact authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Contact Creation

    /// PersonからCNMutableContactを生成
    /// - Parameter person: エクスポートするPerson
    /// - Returns: 生成されたCNMutableContact
    func createContact(from person: Person) -> CNMutableContact {
        let contact = CNMutableContact()

        // 氏名
        let nameComponents = person.name.split(separator: " ", maxSplits: 1)
        if nameComponents.count >= 2 {
            contact.familyName = String(nameComponents[0])
            contact.givenName = String(nameComponents[1])
        } else {
            // スペースがない場合は全体を姓として設定
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
            // 会社名
            if let company = latestCard.company {
                contact.organizationName = company
            }

            // 部署
            if let department = latestCard.department {
                contact.departmentName = department
            }

            // 役職
            if let title = latestCard.title {
                contact.jobTitle = title
            }

            // 電話番号
            contact.phoneNumbers = latestCard.phoneNumbers.map { number in
                CNLabeledValue(
                    label: CNLabelWork,
                    value: CNPhoneNumber(stringValue: number)
                )
            }

            // メールアドレス
            contact.emailAddresses = latestCard.emails.map { email in
                CNLabeledValue(
                    label: CNLabelWork,
                    value: email as NSString
                )
            }

            // 住所
            if let addressString = latestCard.address {
                let postalAddress = CNMutablePostalAddress()
                postalAddress.street = addressString
                postalAddress.country = "日本"
                contact.postalAddresses = [
                    CNLabeledValue(label: CNLabelWork, value: postalAddress)
                ]
            }

            // Webサイト
            if let website = latestCard.website {
                contact.urlAddresses = [
                    CNLabeledValue(label: CNLabelWork, value: website as NSString)
                ]
            }
        }

        // メモ（アプリ名とエクスポート日時を記録）
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let exportDate = dateFormatter.string(from: Date())
        contact.note = "MeishiAppからエクスポート (\(exportDate))"

        return contact
    }

    // MARK: - Contact Saving

    /// 連絡先を保存
    /// - Parameter contact: 保存するCNMutableContact
    func saveContact(_ contact: CNMutableContact) async throws {
        if authorizationStatus != .authorized {
            let authorized = await requestAuthorization()
            if !authorized {
                throw ContactServiceError.notAuthorized
            }
        }

        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)

        do {
            try contactStore.execute(saveRequest)
            logger.info("Contact saved successfully: \(contact.familyName) \(contact.givenName)")
        } catch {
            logger.error("Failed to save contact: \(error.localizedDescription)")
            throw ContactServiceError.saveFailed(error)
        }
    }

    /// Personを連絡先にエクスポート
    /// - Parameter person: エクスポートするPerson
    func exportPerson(_ person: Person) async throws {
        let contact = createContact(from: person)
        try await saveContact(contact)
    }

    // MARK: - Duplicate Check

    /// 同名の連絡先が存在するかチェック
    /// - Parameter name: チェックする名前
    /// - Returns: 既存の連絡先があればそのリスト
    func findExistingContacts(name: String) async throws -> [CNContact] {
        guard authorizationStatus == .authorized else {
            return []
        }

        let predicate = CNContact.predicateForContacts(matchingName: name)
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        do {
            let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            return contacts
        } catch {
            logger.error("Failed to fetch contacts: \(error.localizedDescription)")
            return []
        }
    }

    /// 同名の連絡先が存在するかチェック
    /// - Parameter person: チェックするPerson
    /// - Returns: 既存の連絡先があればtrue
    func hasExistingContact(for person: Person) async -> Bool {
        do {
            let existing = try await findExistingContacts(name: person.name)
            return !existing.isEmpty
        } catch {
            return false
        }
    }
}

// MARK: - ContactServiceError

enum ContactServiceError: LocalizedError {
    case notAuthorized
    case saveFailed(Error)
    case alreadyExists

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return String(localized: "contact.permission.message")
        case .saveFailed:
            return String(localized: "error.contactSaveFailed")
        case .alreadyExists:
            return String(localized: "error.contactAlreadyExists")
        }
    }
}

// MARK: - ContactPreviewView

import SwiftUI

/// 連絡先保存前のプレビュー画面。
struct ContactPreviewView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss

    let person: Person
    let onSave: () -> Void

    @State private var contact: CNMutableContact?
    @State private var existingContacts: [CNContact] = []
    @State private var isCheckingDuplicate = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingSuccess = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                if isCheckingDuplicate {
                    Section {
                        HStack {
                            ProgressView()
                            Text("確認中...")
                        }
                    }
                } else {
                    // 警告セクション（重複がある場合）
                    if !existingContacts.isEmpty {
                        Section {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(localized: "error.contactAlreadyExists"))
                                        .fontWeight(.medium)
                                    Text("同名の連絡先が\(existingContacts.count)件あります")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    // プレビュー内容
                    if let contact = contact {
                        contactPreviewSection(contact)
                    }
                }

                // エラー表示
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(String(localized: "contact.preview.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "contact.save")) {
                        Task {
                            await saveContact()
                        }
                    }
                    .disabled(isCheckingDuplicate || isSaving)
                }
            }
            .alert(String(localized: "contact.saved"), isPresented: $showingSuccess) {
                Button(String(localized: "common.ok")) {
                    onSave()
                    dismiss()
                }
            }
            .task {
                await preparePreview()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func contactPreviewSection(_ contact: CNMutableContact) -> some View {
        // 基本情報
        Section(header: Text(String(localized: "person.name"))) {
            if !contact.familyName.isEmpty || !contact.givenName.isEmpty {
                LabeledContent("名前") {
                    Text("\(contact.familyName) \(contact.givenName)")
                }
            }

            if !contact.phoneticFamilyName.isEmpty || !contact.phoneticGivenName.isEmpty {
                LabeledContent("ふりがな") {
                    Text("\(contact.phoneticFamilyName) \(contact.phoneticGivenName)")
                }
            }
        }

        // 会社情報
        if !contact.organizationName.isEmpty || !contact.jobTitle.isEmpty {
            Section(header: Text(String(localized: "person.company"))) {
                if !contact.organizationName.isEmpty {
                    LabeledContent("会社名") {
                        Text(contact.organizationName)
                    }
                }

                if !contact.departmentName.isEmpty {
                    LabeledContent("部署") {
                        Text(contact.departmentName)
                    }
                }

                if !contact.jobTitle.isEmpty {
                    LabeledContent("役職") {
                        Text(contact.jobTitle)
                    }
                }
            }
        }

        // 連絡先
        if !contact.phoneNumbers.isEmpty || !contact.emailAddresses.isEmpty {
            Section(header: Text("連絡先")) {
                ForEach(contact.phoneNumbers, id: \.identifier) { phone in
                    LabeledContent(String(localized: "card.phone")) {
                        Text(phone.value.stringValue)
                    }
                }

                ForEach(contact.emailAddresses, id: \.identifier) { email in
                    LabeledContent(String(localized: "card.email")) {
                        Text(email.value as String)
                    }
                }
            }
        }

        // 住所
        if !contact.postalAddresses.isEmpty {
            Section(header: Text(String(localized: "card.address"))) {
                ForEach(contact.postalAddresses, id: \.identifier) { address in
                    Text(address.value.street)
                }
            }
        }

        // Webサイト
        if !contact.urlAddresses.isEmpty {
            Section(header: Text(String(localized: "card.website"))) {
                ForEach(contact.urlAddresses, id: \.identifier) { url in
                    Text(url.value as String)
                }
            }
        }
    }

    // MARK: - Methods

    private func preparePreview() async {
        // 連絡先を生成
        let newContact = await ContactService.shared.createContact(from: person)
        contact = newContact

        // 重複チェック
        do {
            existingContacts = try await ContactService.shared.findExistingContacts(name: person.name)
        } catch {
            existingContacts = []
        }

        isCheckingDuplicate = false
    }

    private func saveContact() async {
        guard let contact = contact else { return }

        isSaving = true
        errorMessage = nil

        do {
            try await ContactService.shared.saveContact(contact)
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - Preview

#Preview {
    ContactPreviewView(
        person: Person(name: "山田 太郎", primaryCompany: "株式会社サンプル"),
        onSave: {}
    )
}
