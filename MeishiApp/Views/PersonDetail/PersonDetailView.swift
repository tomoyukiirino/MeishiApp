import SwiftUI
import SwiftData

// MARK: - PersonDetailView

/// 人の詳細画面。名刺履歴・出会いの記録を表示する。
struct PersonDetailView: View {
    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.updatedAt, order: .reverse) private var allPersons: [Person]

    @Bindable var person: Person

    @State private var faceImage: UIImage?
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var showingContactPreview = false
    @State private var showingFacePhotoSelection = false
    @State private var showingTagManagement = false
    @State private var showingExport = false
    @State private var showingMerge = false

    // MARK: - Body

    var body: some View {
        List {
            // 顔写真・基本情報セクション
            profileSection

            // メモセクション
            memoSection

            // タグセクション
            tagsSection

            // 名刺履歴セクション
            if !person.businessCards.isEmpty {
                businessCardsSection
            }

            // 出会いの記録セクション
            if !person.encounters.isEmpty {
                encountersSection
            }

            // アクションセクション
            actionsSection

            // 危険な操作セクション
            dangerZoneSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isEditing = true
                    } label: {
                        Label(String(localized: "common.edit"), systemImage: "pencil")
                    }

                    Button {
                        showingExport = true
                    } label: {
                        Label(String(localized: "export.title"), systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            PersonEditView(person: person)
        }
        .sheet(isPresented: $showingContactPreview) {
            ContactPreviewView(person: person) {
                // 保存成功時のコールバック
            }
        }
        .sheet(isPresented: $showingFacePhotoSelection) {
            FacePhotoSelectionView(person: person)
        }
        .sheet(isPresented: $showingTagManagement) {
            TagManagementView(person: person)
        }
        .sheet(isPresented: $showingExport) {
            ExportView(persons: [person])
        }
        .sheet(isPresented: $showingMerge) {
            PersonMergeView(
                sourcePerson: person,
                allPersons: allPersons.filter { $0.id != person.id }
            )
        }
        .confirmationDialog(
            String(localized: "person.delete.confirm.title"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                deletePerson()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "person.delete.confirm.message", defaultValue: "\(person.name)さんの情報をすべて削除しますか？この操作は取り消せません。"))
        }
        .task {
            await loadFaceImage()
        }
        .onChange(of: person.facePhotoPath) { _, _ in
            Task {
                await loadFaceImage()
            }
        }
    }

    // MARK: - Sections

    /// プロフィールセクション
    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                // 顔写真（タップで編集）
                Button {
                    showingFacePhotoSelection = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        avatarView
                            .frame(width: 80, height: 80)

                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .background(Color.white.clipShape(Circle()))
                    }
                }

                // 基本情報
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let reading = person.nameReading, !reading.isEmpty {
                        Text(reading)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let company = person.primaryCompany, !company.isEmpty {
                        Text(company)
                            .font(.subheadline)
                    }

                    if let title = person.primaryTitle, !title.isEmpty {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    /// メモセクション
    private var memoSection: some View {
        Section(header: Text(String(localized: "person.memo"))) {
            if let memo = person.memo, !memo.isEmpty {
                Text(memo)
                    .font(.body)
            } else {
                Text("メモを追加...")
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        isEditing = true
                    }
            }
        }
    }

    /// タグセクション
    private var tagsSection: some View {
        Section(header: Text(String(localized: "tag.add"))) {
            Button {
                showingTagManagement = true
            } label: {
                HStack {
                    if person.tags.isEmpty {
                        Text("タグを追加...")
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(person.tags) { tag in
                                TagChipView(tag: tag)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    /// 名刺履歴セクション
    private var businessCardsSection: some View {
        Section(header: Text(String(localized: "person.detail.cardHistory"))) {
            ForEach(person.businessCards.sorted { $0.acquiredAt > $1.acquiredAt }) { card in
                NavigationLink(destination: BusinessCardDetailView(card: card)) {
                    BusinessCardRowView(card: card)
                }
            }
        }
    }

    /// 出会いの記録セクション
    private var encountersSection: some View {
        Section(header: Text(String(localized: "person.detail.encounterHistory"))) {
            ForEach(person.encounters.sorted { ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt) }) { encounter in
                EncounterRowView(encounter: encounter)
            }
        }
    }

    /// アクションセクション
    private var actionsSection: some View {
        Section {
            // 連絡先に保存
            Button {
                showingContactPreview = true
            } label: {
                Label(
                    String(localized: "person.detail.exportToContacts"),
                    systemImage: "person.crop.circle.badge.plus"
                )
            }
            .disabled(person.businessCards.isEmpty)

            // この方の写真をもっと見る（Phase 3で有効化）
            Button {
                // TODO: Phase 3で実装
            } label: {
                Label(
                    String(localized: "person.detail.findPhotos"),
                    systemImage: "photo.on.rectangle"
                )
            }
            .disabled(!person.hasFacePhoto) // 顔写真がない場合は無効
        }
    }

    /// 危険な操作セクション
    private var dangerZoneSection: some View {
        Section {
            // 統合ボタン
            Button {
                showingMerge = true
            } label: {
                Label(
                    String(localized: "person.merge.button"),
                    systemImage: "person.2.fill"
                )
            }

            // 削除ボタン
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label(
                    String(localized: "common.delete"),
                    systemImage: "trash"
                )
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var avatarView: some View {
        if let faceImage = faceImage {
            Image(uiImage: faceImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .overlay {
                    if person.hasFacePhoto {
                        ProgressView()
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.gray)
                    }
                }
        }
    }

    // MARK: - Methods

    private func loadFaceImage() async {
        guard let path = person.facePhotoPath else {
            faceImage = nil
            return
        }
        faceImage = await ImageStorageService.shared.loadImage(relativePath: path)
    }

    private func deletePerson() {
        modelContext.delete(person)
        dismiss()
    }
}

// MARK: - BusinessCardDetailView

/// 名刺の詳細画面。
struct BusinessCardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var card: BusinessCard
    @State private var frontImage: UIImage?
    @State private var backImage: UIImage?
    @State private var showingFront = true
    @State private var showingEditSheet = false
    @State private var isRescanning = false
    @State private var rescanError: String?
    @State private var showingRescanSuccess = false
    @State private var showingDeleteConfirmation = false

    /// この名刺がメイン名刺かどうか
    private var isPrimaryCard: Bool {
        card.person?.isPrimaryCard(card) ?? false
    }

    /// 削除可能かどうか（メイン名刺かつ複数名刺がある場合は削除不可）
    private var canDelete: Bool {
        guard let person = card.person else { return true }
        // 名刺が1枚しかない場合は削除可能（人物ごと削除する形になる）
        if person.businessCards.count <= 1 { return true }
        // メイン名刺の場合は削除不可
        return !isPrimaryCard
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 名刺画像
                VStack(spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        if showingFront, let frontImage = frontImage {
                            Image(uiImage: frontImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 4)
                        } else if !showingFront, let backImage = backImage {
                            Image(uiImage: backImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 4)
                        }

                        // メイン名刺バッジ
                        if isPrimaryCard {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                Text(String(localized: "card.primary"))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding(8)
                        }
                    }

                    // 表/裏切り替え
                    if card.hasBackImage {
                        HStack {
                            Button {
                                showingFront = true
                            } label: {
                                Text(String(localized: "card.front"))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(showingFront ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundStyle(showingFront ? .white : .primary)
                                    .clipShape(Capsule())
                            }

                            Button {
                                showingFront = false
                            } label: {
                                Text(String(localized: "card.back"))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(!showingFront ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundStyle(!showingFront ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding()

                // 再スキャンボタン
                Button {
                    Task {
                        await rescanCard()
                    }
                } label: {
                    HStack {
                        if isRescanning {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text(String(localized: "card.rescanning"))
                        } else {
                            Image(systemName: "doc.text.viewfinder")
                            Text(String(localized: "card.rescan"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(isRescanning)
                .padding(.horizontal)

                // エラー表示
                if let error = rescanError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // 名刺情報
                VStack(alignment: .leading, spacing: 16) {
                    if let company = card.company {
                        InfoRow(label: String(localized: "person.company"), value: company)
                    }

                    if let department = card.department {
                        InfoRow(label: String(localized: "person.department"), value: department)
                    }

                    if let title = card.title {
                        InfoRow(label: String(localized: "person.title"), value: title)
                    }

                    if !card.phoneNumbers.isEmpty {
                        InfoRow(label: String(localized: "card.phone"), value: card.phoneNumbers.joined(separator: "\n"))
                    }

                    if !card.emails.isEmpty {
                        InfoRow(label: String(localized: "card.email"), value: card.emails.joined(separator: "\n"))
                    }

                    if let address = card.address {
                        InfoRow(label: String(localized: "card.address"), value: address)
                    }

                    if let website = card.website {
                        InfoRow(label: String(localized: "card.website"), value: website)
                    }

                    InfoRow(label: String(localized: "card.acquiredAt"), value: card.acquiredAtFormatted)
                }
                .padding()
            }
        }
        .navigationTitle(card.company ?? "名刺")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label(String(localized: "common.edit"), systemImage: "pencil")
                    }

                    // メインに設定（メイン名刺でない場合のみ表示）
                    if !isPrimaryCard, let person = card.person, person.businessCards.count > 1 {
                        Button {
                            setAsPrimaryCard()
                        } label: {
                            Label(String(localized: "card.setAsPrimary"), systemImage: "star")
                        }
                    }

                    Divider()

                    // 削除（メイン名刺の場合は無効）
                    if canDelete {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    } else {
                        // メイン名刺は削除不可の説明を表示
                        Button(role: .destructive) {
                            // 何もしない
                        } label: {
                            Label(String(localized: "card.cannotDeletePrimary"), systemImage: "trash.slash")
                        }
                        .disabled(true)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            BusinessCardEditView(card: card)
        }
        .alert(String(localized: "card.rescan.success"), isPresented: $showingRescanSuccess) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "card.rescan.success.message"))
        }
        .confirmationDialog(
            String(localized: "card.delete.confirm.title"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                deleteCard()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "card.delete.confirm.message"))
        }
        .task {
            frontImage = await ImageStorageService.shared.loadImage(relativePath: card.frontImagePath)
            if let backPath = card.backImagePath {
                backImage = await ImageStorageService.shared.loadImage(relativePath: backPath)
            }
        }
    }

    // MARK: - Set as Primary Card

    private func setAsPrimaryCard() {
        card.person?.setPrimaryCard(card)
    }

    // MARK: - Delete Card

    private func deleteCard() {
        let frontPath = card.frontImagePath
        let backPath = card.backImagePath

        // Personから名刺を除去
        if let person = card.person {
            person.businessCards.removeAll { $0.id == card.id }
            person.updatePrimaryInfo()
        }

        // 名刺を削除
        modelContext.delete(card)

        // 画像ファイルを削除（非同期）
        Task {
            await ImageStorageService.shared.deleteImage(relativePath: frontPath)
            if let backPath = backPath {
                await ImageStorageService.shared.deleteImage(relativePath: backPath)
            }
        }

        dismiss()
    }

    // MARK: - Rescan Methods

    /// 名刺を再スキャンしてAI構造化を実行
    private func rescanCard() async {
        isRescanning = true
        rescanError = nil

        do {
            // 表面画像を取得
            guard let frontImg = frontImage else {
                rescanError = String(localized: "error.generic")
                isRescanning = false
                return
            }

            // OCR実行（表面）
            var combinedText = ""

            let frontText = try await OCRService.shared.recognizeText(from: frontImg)
            combinedText = frontText

            // 裏面があればOCR実行
            if let backImg = backImage {
                let backText = try await OCRService.shared.recognizeText(from: backImg)
                if !backText.isEmpty {
                    combinedText += "\n" + backText
                }
                // OCRテキストを更新
                await MainActor.run {
                    card.ocrTextBack = backText
                }
            }

            // OCRテキストを更新
            await MainActor.run {
                card.ocrTextFront = frontText
            }

            // AI構造化を試行
            let hasAPIKey = await ClaudeAPIService.shared.hasAPIKey
            if hasAPIKey {
                let structuredData = try await ClaudeAPIService.shared.structure(
                    image: frontImg,
                    ocrText: combinedText
                )

                // 構造化データを適用
                await MainActor.run {
                    applyStructuredData(structuredData)
                    card.person?.updatePrimaryInfo()
                    showingRescanSuccess = true
                }
            } else {
                // APIキーがない場合は正規表現で抽出
                await MainActor.run {
                    extractAndApplyData(from: combinedText)
                    card.person?.updatePrimaryInfo()
                    showingRescanSuccess = true
                }
            }
        } catch {
            await MainActor.run {
                rescanError = error.localizedDescription
            }
        }

        await MainActor.run {
            isRescanning = false
        }
    }

    /// AI構造化データを適用
    private func applyStructuredData(_ data: StructuredCardData) {
        if let value = data.company, !value.isEmpty {
            card.company = value
        }
        if let value = data.department, !value.isEmpty {
            card.department = value
        }
        if let value = data.title, !value.isEmpty {
            card.title = value
        }
        if let phones = data.phoneNumbers, !phones.isEmpty {
            card.phoneNumbers = phones
        }
        if let mails = data.emails, !mails.isEmpty {
            card.emails = mails
        }
        if let value = data.address, !value.isEmpty {
            card.address = value
        }
        if let value = data.website, !value.isEmpty {
            card.website = value
        }

        // Personの名前・ふりがなも更新
        if let person = card.person {
            if let name = data.name, !name.isEmpty {
                person.name = name
            }
            if let reading = data.nameReading, !reading.isEmpty {
                person.nameReading = reading
            }
        }
    }

    /// 正規表現でデータを抽出して適用（フォールバック）
    private func extractAndApplyData(from text: String) {
        // メールアドレス
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        if let regex = try? NSRegularExpression(pattern: emailPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            let email = String(text[range])
            if !card.emails.contains(email) {
                card.emails = [email] + card.emails
            }
        }

        // 電話番号
        let phonePattern = #"(?:TEL|tel|Tel|電話)?[:\s]?(\d{2,4}[-‐ー]\d{2,4}[-‐ー]\d{3,4})"#
        if let regex = try? NSRegularExpression(pattern: phonePattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let phone = String(text[range])
            if !card.phoneNumbers.contains(phone) {
                card.phoneNumbers = [phone] + card.phoneNumbers
            }
        }

        // URL
        let urlPattern = #"https?://[^\s]+"#
        if let regex = try? NSRegularExpression(pattern: urlPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            card.website = String(text[range])
        }
    }
}

// MARK: - BusinessCardEditView

/// 名刺の編集画面。
struct BusinessCardEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var card: BusinessCard

    @State private var company: String = ""
    @State private var department: String = ""
    @State private var title: String = ""
    @State private var phoneNumbers: [String] = [""]
    @State private var emails: [String] = [""]
    @State private var address: String = ""
    @State private var website: String = ""
    @State private var acquiredAt: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                // 会社・役職
                Section(header: Text(String(localized: "person.company"))) {
                    TextField(String(localized: "person.company"), text: $company)
                    TextField(String(localized: "person.department"), text: $department)
                    TextField(String(localized: "person.title"), text: $title)
                }

                // 電話番号
                Section(header: Text(String(localized: "card.phone"))) {
                    ForEach(phoneNumbers.indices, id: \.self) { index in
                        HStack {
                            TextField(String(localized: "card.phone"), text: $phoneNumbers[index])
                                .keyboardType(.phonePad)
                            if phoneNumbers.count > 1 {
                                Button {
                                    phoneNumbers.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    Button {
                        phoneNumbers.append("")
                    } label: {
                        Label(String(localized: "registration.addPhoneNumber"), systemImage: "plus")
                    }
                }

                // メールアドレス
                Section(header: Text(String(localized: "card.email"))) {
                    ForEach(emails.indices, id: \.self) { index in
                        HStack {
                            TextField(String(localized: "card.email"), text: $emails[index])
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                            if emails.count > 1 {
                                Button {
                                    emails.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    Button {
                        emails.append("")
                    } label: {
                        Label(String(localized: "registration.addEmail"), systemImage: "plus")
                    }
                }

                // 住所・Webサイト
                Section {
                    TextField(String(localized: "card.address"), text: $address)
                    TextField(String(localized: "card.website"), text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }

                // 取得日
                Section(header: Text(String(localized: "card.acquiredAt"))) {
                    DatePicker(
                        String(localized: "card.acquiredAt"),
                        selection: $acquiredAt,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                }
            }
            .navigationTitle(String(localized: "common.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) {
                        saveCard()
                    }
                }
            }
            .onAppear {
                loadCardData()
            }
        }
    }

    private func loadCardData() {
        company = card.company ?? ""
        department = card.department ?? ""
        title = card.title ?? ""
        phoneNumbers = card.phoneNumbers.isEmpty ? [""] : card.phoneNumbers
        emails = card.emails.isEmpty ? [""] : card.emails
        address = card.address ?? ""
        website = card.website ?? ""
        acquiredAt = card.acquiredAt
    }

    private func saveCard() {
        card.company = company.isEmpty ? nil : company
        card.department = department.isEmpty ? nil : department
        card.title = title.isEmpty ? nil : title
        card.phoneNumbers = phoneNumbers.filter { !$0.isEmpty }
        card.emails = emails.filter { !$0.isEmpty }
        card.address = address.isEmpty ? nil : address
        card.website = website.isEmpty ? nil : website
        card.acquiredAt = acquiredAt

        // Personの情報も更新
        card.person?.updatePrimaryInfo()

        dismiss()
    }
}

// MARK: - InfoRow

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

// MARK: - BusinessCardRowView

/// 名刺履歴の1行を表示するビュー。
struct BusinessCardRowView: View {
    let card: BusinessCard
    @State private var frontImage: UIImage?

    /// この名刺がメイン名刺かどうか
    private var isPrimaryCard: Bool {
        card.person?.isPrimaryCard(card) ?? false
    }

    var body: some View {
        HStack(spacing: 12) {
            // 名刺サムネイル
            ZStack(alignment: .topLeading) {
                if let frontImage = frontImage {
                    Image(uiImage: frontImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 36)
                        .overlay {
                            Image(systemName: "rectangle.portrait")
                                .foregroundStyle(.gray)
                        }
                }

                // メインバッジ
                if isPrimaryCard {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .background(
                            Circle()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                        )
                        .offset(x: -4, y: -4)
                }
            }

            // 情報
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let company = card.company {
                        Text(company)
                            .font(.subheadline)
                    }
                    if isPrimaryCard {
                        Text(String(localized: "card.primary"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                if let title = card.title {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(card.acquiredAtFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .task {
            frontImage = await ImageStorageService.shared.loadImage(relativePath: card.frontImagePath)
        }
    }
}

// MARK: - EncounterRowView

/// 出会いの記録の1行を表示するビュー。
struct EncounterRowView: View {
    let encounter: Encounter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eventName = encounter.eventName, !eventName.isEmpty {
                Text(eventName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            HStack {
                if let location = encounter.location, !location.isEmpty {
                    Label(location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let dateFormatted = encounter.dateFormatted {
                    Label(dateFormatted, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let memo = encounter.memo, !memo.isEmpty {
                Text(memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TagChipView

/// タグのチップ表示。
struct TagChipView: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
    }
}

// MARK: - FlowLayout

/// フレキシブルなフローレイアウト。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}

// MARK: - PersonEditView

/// 人の編集画面。
struct PersonEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var person: Person

    @State private var name: String = ""
    @State private var nameReading: String = ""
    @State private var memo: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "person.name"))) {
                    TextField(String(localized: "person.name"), text: $name)
                    TextField(String(localized: "person.nameReading"), text: $nameReading)
                }

                Section(header: Text(String(localized: "person.memo"))) {
                    TextEditor(text: $memo)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(String(localized: "common.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) {
                        savePerson()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = person.name
                nameReading = person.nameReading ?? ""
                memo = person.memo ?? ""
            }
        }
    }

    private func savePerson() {
        person.name = name
        person.nameReading = nameReading.isEmpty ? nil : nameReading
        person.memo = memo.isEmpty ? nil : memo
        person.updatedAt = Date()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PersonDetailView(person: Person(name: "山田太郎", primaryCompany: "株式会社サンプル", primaryTitle: "代表取締役"))
    }
    .modelContainer(for: [Person.self, BusinessCard.self, Encounter.self, Tag.self], inMemory: true)
}
