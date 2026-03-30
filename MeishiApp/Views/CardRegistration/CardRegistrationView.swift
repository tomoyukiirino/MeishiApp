import SwiftUI
import SwiftData

// MARK: - CardRegistrationView

/// 名刺登録フロー画面。
/// OCR → 構造化 → 重複検出 → 保存。
struct CardRegistrationView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let frontImage: UIImage
    let backImage: UIImage?

    @State private var viewModel: CardRegistrationViewModel

    // MARK: - Initialization

    init(frontImage: UIImage, backImage: UIImage? = nil) {
        self.frontImage = frontImage
        self.backImage = backImage
        self._viewModel = State(initialValue: CardRegistrationViewModel(
            frontImage: frontImage,
            backImage: backImage
        ))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.currentStep {
                case .ocr:
                    ocrProgressView
                case .structuring:
                    structuringFormView
                case .duplicateDetected:
                    duplicateDetectionView
                case .infoSelection:
                    infoSelectionView
                case .saving:
                    savingProgressView
                case .completed:
                    completedView
                }
            }
            .navigationTitle(String(localized: "registration.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.startOCR()
            }
        }
    }

    // MARK: - Step Views

    /// OCR処理中の表示
    private var ocrProgressView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(String(localized: "ocr.processing"))
                .font(.headline)

            // 名刺画像プレビュー
            Image(uiImage: frontImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 4)
        }
        .padding()
    }

    /// 構造化フォーム
    private var structuringFormView: some View {
        Form {
            // 名刺画像プレビュー
            Section {
                CardImagePreview(frontImage: frontImage, backImage: backImage)
            }

            // 氏名（必須）
            Section(header: Text(String(localized: "person.name"))) {
                TextField(String(localized: "person.name"), text: $viewModel.name)
                TextField(String(localized: "person.nameReading"), text: $viewModel.nameReading)
            }

            // 会社・役職
            Section(header: Text(String(localized: "person.company"))) {
                TextField(String(localized: "person.company"), text: $viewModel.company)
                TextField(String(localized: "person.department"), text: $viewModel.department)
                TextField(String(localized: "person.title"), text: $viewModel.title)
            }

            // 連絡先
            Section(header: Text(String(localized: "card.phone"))) {
                ForEach(viewModel.phoneNumbers.indices, id: \.self) { index in
                    HStack {
                        TextField(String(localized: "card.phone"), text: $viewModel.phoneNumbers[index])
                            .keyboardType(.phonePad)
                        Button {
                            viewModel.removePhoneNumber(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                Button {
                    viewModel.addPhoneNumber()
                } label: {
                    Label(String(localized: "registration.addPhoneNumber"), systemImage: "plus")
                }
            }

            Section(header: Text(String(localized: "card.email"))) {
                ForEach(viewModel.emails.indices, id: \.self) { index in
                    HStack {
                        TextField(String(localized: "card.email"), text: $viewModel.emails[index])
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        Button {
                            viewModel.removeEmail(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                Button {
                    viewModel.addEmail()
                } label: {
                    Label(String(localized: "registration.addEmail"), systemImage: "plus")
                }
            }

            // 住所・Webサイト
            Section {
                TextField(String(localized: "card.address"), text: $viewModel.address)
                TextField(String(localized: "card.website"), text: $viewModel.website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
            }

            // 取得日・メモ
            Section(header: Text(String(localized: "card.acquiredAt"))) {
                DatePicker(
                    String(localized: "card.acquiredAt"),
                    selection: $viewModel.acquiredDate,
                    displayedComponents: [.date]
                )
            }

            Section(header: Text(String(localized: "card.memo"))) {
                TextEditor(text: $viewModel.memo)
                    .frame(minHeight: 80)
            }

            // OCR結果（コピー・編集可能）
            if viewModel.ocrTextFront != nil || viewModel.ocrTextBack != nil {
                Section(header: Text(String(localized: "ocr.extracted"))) {
                    TextEditor(text: Binding(
                        get: {
                            var text = viewModel.ocrTextFront ?? ""
                            if let backText = viewModel.ocrTextBack, !backText.isEmpty {
                                if !text.isEmpty { text += "\n\n--- 裏面 ---\n" }
                                text += backText
                            }
                            return text
                        },
                        set: { _ in }
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 100)
                    .textSelection(.enabled)
                }
            }

            // バリデーションエラー
            if let error = viewModel.validationError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            // 保存ボタン
            Section {
                Button {
                    viewModel.proceedToSave(modelContext: modelContext)
                } label: {
                    Text(String(localized: "common.save"))
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .disabled(!viewModel.isValid)
            }
        }
    }

    /// 重複検出ビュー
    private var duplicateDetectionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.badge.clock")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text(String(localized: "duplicate.found.title"))
                .font(.title2)
                .fontWeight(.semibold)

            if let candidate = viewModel.duplicateCandidate {
                Text(String(localized: "duplicate.found.message", defaultValue: "\(candidate.person.name)さんは既に登録されています。"))
                    .multilineTextAlignment(.center)

                // 既存の人の情報
                VStack(alignment: .leading, spacing: 8) {
                    Text(candidate.person.name)
                        .font(.headline)
                    if let company = candidate.person.primaryCompany {
                        Text(company)
                            .foregroundStyle(.secondary)
                    }
                    Text("名刺: \(candidate.person.businessCardCount)枚")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(spacing: 12) {
                // 既存の人に追加
                Button {
                    viewModel.addToExistingPerson()
                } label: {
                    Text(String(localized: "duplicate.addToExisting"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // 新規登録
                Button {
                    viewModel.registerAsNewPerson(modelContext: modelContext)
                } label: {
                    Text(String(localized: "duplicate.registerAsNew"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }

    /// 情報選択ビュー（既存の人に追加時、どの情報を保持するか選択）
    private var infoSelectionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ヘッダー
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)

                    Text(String(localized: "duplicate.selectInfo.title"))
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(String(localized: "duplicate.selectInfo.message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                // 既存の情報
                if let existingPerson = viewModel.targetPerson {
                    infoOptionCard(
                        title: String(localized: "duplicate.existingInfo"),
                        name: existingPerson.name,
                        nameReading: existingPerson.nameReading,
                        company: existingPerson.primaryCompany,
                        title_: existingPerson.primaryTitle,
                        isSelected: viewModel.useExistingInfo,
                        action: { viewModel.selectExistingInfo() }
                    )
                }

                // 新しい情報
                infoOptionCard(
                    title: String(localized: "duplicate.newInfo"),
                    name: viewModel.name,
                    nameReading: viewModel.nameReading.isEmpty ? nil : viewModel.nameReading,
                    company: viewModel.company.isEmpty ? nil : viewModel.company,
                    title_: viewModel.title.isEmpty ? nil : viewModel.title,
                    isSelected: !viewModel.useExistingInfo,
                    action: { viewModel.selectNewInfo() }
                )

                // 確定ボタン
                Button {
                    viewModel.confirmInfoSelection(modelContext: modelContext)
                } label: {
                    Text(String(localized: "duplicate.confirmAndSave"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.horizontal)
        }
    }

    /// 情報選択カード
    private func infoOptionCard(
        title: String,
        name: String,
        nameReading: String?,
        company: String?,
        title_: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .blue : .secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let reading = nameReading, !reading.isEmpty {
                        Text(reading)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let company = company {
                        HStack(spacing: 4) {
                            Text(company)
                            if let title_ = title_ {
                                Text("・")
                                Text(title_)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    /// 保存中の表示
    private var savingProgressView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(String(localized: "common.processing"))
        }
    }

    /// 完了表示
    private var completedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text(String(localized: "common.done"))
                .font(.title2)
                .fontWeight(.semibold)

            Button {
                dismiss()
            } label: {
                Text(String(localized: "common.close"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - CardImagePreview

/// 名刺画像プレビュー（表/裏切り替え可能）。
struct CardImagePreview: View {
    let frontImage: UIImage
    let backImage: UIImage?

    @State private var showingBack = false

    var body: some View {
        VStack {
            if showingBack, let backImage = backImage {
                Image(uiImage: backImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(uiImage: frontImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if backImage != nil {
                HStack {
                    Button {
                        showingBack = false
                    } label: {
                        Text(String(localized: "card.front"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(showingBack ? Color.gray.opacity(0.2) : Color.blue)
                            .foregroundColor(showingBack ? .primary : .white)
                            .clipShape(Capsule())
                    }

                    Button {
                        showingBack = true
                    } label: {
                        Text(String(localized: "card.back"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(showingBack ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(showingBack ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - CardRegistrationViewModel

/// 名刺登録画面のViewModel。
@Observable
final class CardRegistrationViewModel {
    // MARK: - Types

    enum RegistrationStep {
        case ocr
        case structuring
        case duplicateDetected
        case infoSelection  // 情報選択画面（既存の人に追加時）
        case saving
        case completed
    }

    // MARK: - Properties

    let frontImage: UIImage
    let backImage: UIImage?

    var currentStep: RegistrationStep = .ocr

    // 構造化データ
    var name = ""
    var nameReading = ""
    var company = ""
    var department = ""
    var title = ""
    var phoneNumbers: [String] = [""]
    var emails: [String] = [""]
    var address = ""
    var website = ""

    // OCR結果
    var ocrTextFront: String?
    var ocrTextBack: String?

    // 取得日・メモ
    var acquiredDate = Date()
    var memo = ""

    // 重複検出
    var duplicateCandidate: DuplicateCandidate?
    var targetPerson: Person?

    // 情報選択（既存の人に追加時）
    var selectedName: String = ""
    var selectedNameReading: String?
    var useExistingInfo: Bool = true  // true: 既存情報を維持、false: 新規情報を使用

    // バリデーション
    var validationError: String?

    // MARK: - Initialization

    init(frontImage: UIImage, backImage: UIImage? = nil) {
        self.frontImage = frontImage
        self.backImage = backImage
    }

    // MARK: - Computed Properties

    var isValid: Bool {
        // 氏名または会社名のいずれかが必要
        !name.trimmingCharacters(in: .whitespaces).isEmpty ||
        !company.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - OCR

    func startOCR() async {
        // OCRを実行
        let frontText: String
        let backText: String?

        do {
            let result = try await OCRService.shared.recognizeBusinessCard(
                frontImage: frontImage,
                backImage: backImage
            )
            frontText = result.front
            backText = result.back
        } catch {
            await MainActor.run {
                // OCR失敗時も構造化画面に進む（手動入力）
                currentStep = .structuring
            }
            return
        }

        await MainActor.run {
            ocrTextFront = frontText
            ocrTextBack = backText
        }

        // AI構造化を試行（LLMサービスが利用可能な場合）
        let llmSettings = LLMSettingsManager.shared
        if let llmService = LLMServiceFactory.shared.createService() {
            await MainActor.run {
                currentStep = .ocr // AI構造化中の表示を維持
            }

            do {
                let combinedText = frontText + (backText.map { "\n" + $0 } ?? "")
                let structuredData = try await llmService.structure(
                    image: frontImage,
                    ocrText: combinedText,
                    mode: llmSettings.privacyMode
                )

                await MainActor.run {
                    applyStructuredData(structuredData)
                    currentStep = .structuring
                }
            } catch {
                // AI構造化失敗時は簡易構造化にフォールバック
                print("AI構造化エラー: \(error.localizedDescription)")
                await MainActor.run {
                    extractStructuredDataSync(from: frontText + (backText ?? ""))
                    currentStep = .structuring
                }
            }
        } else {
            // LLMサービスが利用できない場合は簡易構造化
            await MainActor.run {
                extractStructuredDataSync(from: frontText + (backText ?? ""))
                currentStep = .structuring
            }
        }
    }

    /// AI構造化の結果を適用
    private func applyStructuredData(_ data: BusinessCardStructuredData) {
        if let value = data.name, !value.isEmpty { name = value }
        if let value = data.nameReading, !value.isEmpty { nameReading = value }
        if let value = data.company, !value.isEmpty { company = value }
        if let value = data.department, !value.isEmpty { department = value }
        if let value = data.title, !value.isEmpty { title = value }
        if let values = data.phoneNumbers, !values.isEmpty { phoneNumbers = values }
        if let values = data.emails, !values.isEmpty { emails = values }
        if let value = data.address, !value.isEmpty { address = value }
        if let value = data.website, !value.isEmpty { website = value }
    }

    /// 同期的にテキストから構造化データを抽出（簡略版）
    private func extractStructuredDataSync(from text: String) {
        // 電話番号を抽出
        let phonePattern = #"(?:0\d{1,4})[-(（]?\d{1,4}[-)）]?\d{3,4}"#
        if let regex = try? NSRegularExpression(pattern: phonePattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            let phones = matches.compactMap { match -> String? in
                guard let range = Range(match.range, in: text) else { return nil }
                return String(text[range])
            }
            if !phones.isEmpty {
                phoneNumbers = phones
            }
        }

        // メールアドレスを抽出
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        if let regex = try? NSRegularExpression(pattern: emailPattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            let extractedEmails = matches.compactMap { match -> String? in
                guard let range = Range(match.range, in: text) else { return nil }
                return String(text[range]).lowercased()
            }
            if !extractedEmails.isEmpty {
                emails = extractedEmails
            }
        }

        // 住所を抽出（郵便番号または都道府県を含む行）
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 郵便番号パターン
            if trimmed.range(of: #"〒?\s*\d{3}[-ー－]?\d{4}"#, options: .regularExpression) != nil {
                address = trimmed
                break
            }
            // 都道府県を含む行
            if trimmed.contains("都") || trimmed.contains("道") ||
               trimmed.contains("府") || trimmed.contains("県") {
                if !trimmed.contains("@") && !trimmed.contains("TEL") && !trimmed.hasPrefix("0") {
                    address = trimmed
                    break
                }
            }
        }

        // URLを抽出
        let urlPattern = #"(?:https?://)?(?:www\.)?[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z]{2,}(?:/[^\s]*)?"#
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            var url = String(text[range])
            // メールアドレスを除外
            if !url.contains("@") {
                if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
                    url = "https://" + url
                }
                website = url
            }
        }
    }

    // MARK: - Navigation

    func proceedToSave(modelContext: ModelContext) {
        // バリデーション
        guard isValid else {
            validationError = String(localized: "registration.nameOrCompanyRequired")
            return
        }

        validationError = nil

        // 重複検出
        let detector = DuplicateDetector(modelContext: modelContext)
        if let candidate = detector.findBestMatch(
            name: name.isEmpty ? nil : name,
            company: company.isEmpty ? nil : company,
            email: emails.first?.isEmpty == false ? emails.first : nil
        ) {
            duplicateCandidate = candidate
            currentStep = .duplicateDetected
        } else {
            // 重複なし - 直接保存
            Task {
                await saveCard(modelContext: modelContext)
            }
        }
    }

    func addToExistingPerson() {
        guard let candidate = duplicateCandidate else { return }
        targetPerson = candidate.person
        // デフォルトは既存の情報を維持
        selectedName = candidate.person.name
        selectedNameReading = candidate.person.nameReading
        useExistingInfo = true
        currentStep = .infoSelection
    }

    func confirmInfoSelection(modelContext: ModelContext) {
        Task {
            await saveCard(modelContext: modelContext)
        }
    }

    func registerAsNewPerson(modelContext: ModelContext) {
        targetPerson = nil
        duplicateCandidate = nil
        Task {
            await saveCard(modelContext: modelContext)
        }
    }

    func selectExistingInfo() {
        guard let person = targetPerson else { return }
        selectedName = person.name
        selectedNameReading = person.nameReading
        useExistingInfo = true
    }

    func selectNewInfo() {
        selectedName = name
        selectedNameReading = nameReading.isEmpty ? nil : nameReading
        useExistingInfo = false
    }

    // MARK: - Phone/Email Management

    func addPhoneNumber() {
        phoneNumbers.append("")
    }

    func removePhoneNumber(at index: Int) {
        guard phoneNumbers.count > 1 else { return }
        phoneNumbers.remove(at: index)
    }

    func addEmail() {
        emails.append("")
    }

    func removeEmail(at index: Int) {
        guard emails.count > 1 else { return }
        emails.remove(at: index)
    }

    // MARK: - Save

    @MainActor
    func saveCard(modelContext: ModelContext) async {
        currentStep = .saving

        do {
            // 画像を保存
            let cardId = UUID()
            let frontPath = try await ImageStorageService.shared.saveCardFrontImage(frontImage, cardId: cardId)
            let backPath: String?
            if let backImage = backImage {
                backPath = try await ImageStorageService.shared.saveCardBackImage(backImage, cardId: cardId)
            } else {
                backPath = nil
            }

            // BusinessCard作成
            let card = BusinessCard(
                id: cardId,
                frontImagePath: frontPath,
                backImagePath: backPath,
                company: company.isEmpty ? nil : company,
                department: department.isEmpty ? nil : department,
                title: title.isEmpty ? nil : title,
                phoneNumbers: phoneNumbers.filter { !$0.isEmpty },
                emails: emails.filter { !$0.isEmpty },
                address: address.isEmpty ? nil : address,
                website: website.isEmpty ? nil : website,
                ocrTextFront: ocrTextFront,
                ocrTextBack: ocrTextBack,
                acquiredAt: acquiredDate
            )

            // Person作成または取得
            let person: Person
            if let existing = targetPerson {
                person = existing
                // ユーザーが選択した情報を適用
                person.name = selectedName
                person.nameReading = selectedNameReading
                // 新しい情報を選択した場合は会社名・役職も更新
                if !useExistingInfo {
                    if !company.isEmpty {
                        person.primaryCompany = company
                    }
                    if !title.isEmpty {
                        person.primaryTitle = title
                    }
                }
            } else {
                person = Person(
                    name: name.isEmpty ? company : name,
                    nameReading: nameReading.isEmpty ? nil : nameReading,
                    primaryCompany: company.isEmpty ? nil : company,
                    primaryTitle: title.isEmpty ? nil : title
                )
                modelContext.insert(person)
            }

            // 名刺をPersonに紐づけ
            card.person = person
            person.businessCards.append(card)
            modelContext.insert(card)

            // メモがある場合のみEncounter作成
            if !memo.isEmpty {
                let encounter = Encounter(
                    person: person,
                    eventName: nil,
                    date: acquiredDate,
                    location: nil,
                    memo: memo,
                    businessCard: card
                )
                person.encounters.append(encounter)
                modelContext.insert(encounter)
            }

            // Personの情報を更新（会社名、役職）
            person.updatePrimaryInfo()

            currentStep = .completed
        } catch {
            validationError = error.localizedDescription
            currentStep = .structuring
        }
    }
}

// MARK: - Preview

#Preview {
    CardRegistrationView(
        frontImage: UIImage(systemName: "rectangle.portrait")!
    )
    .modelContainer(for: [Person.self, BusinessCard.self, Encounter.self, Tag.self], inMemory: true)
}
