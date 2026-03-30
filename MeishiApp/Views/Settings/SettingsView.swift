import SwiftUI
import SwiftData

// MARK: - SettingsView

/// 設定画面。
struct SettingsView: View {
    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Query private var allTags: [Tag]

    @State private var showingAuthError = false
    @State private var authErrorMessage = ""

    // AI構造化設定
    @ObservedObject private var llmSettings = LLMSettingsManager.shared

    // バックアップ設定
    @State private var iCloudBackupEnabled = false
    @State private var isCreatingBackup = false
    @State private var isRestoring = false
    @State private var showingBackupSuccess = false
    @State private var showingRestoreSuccess = false
    @State private var showingBackupError = false
    @State private var showingRestoreFilePicker = false
    @State private var backupErrorMessage = ""

    // インポート
    @State private var showingImportView = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // セキュリティセクション
                securitySection

                // AI構造化セクション（Phase 2）
                aiStructuringSection

                // タグ管理セクション（Phase 2）
                tagManagementSection

                // データ管理セクション
                dataManagementSection

                // OCR設定セクション
                ocrSection

                // バックアップセクション
                backupSection

                // このアプリについて
                aboutSection
            }
            .navigationTitle(String(localized: "settings.title"))
            .alert(
                String(localized: "error.generic"),
                isPresented: $showingAuthError
            ) {
                Button(String(localized: "common.ok")) {}
            } message: {
                Text(authErrorMessage)
            }
            .alert(
                String(localized: "backup.success"),
                isPresented: $showingBackupSuccess
            ) {
                Button(String(localized: "common.ok")) {}
            }
            .alert(
                String(localized: "backup.restored"),
                isPresented: $showingRestoreSuccess
            ) {
                Button(String(localized: "common.ok")) {}
            }
            .alert(
                String(localized: "error.generic"),
                isPresented: $showingBackupError
            ) {
                Button(String(localized: "common.ok")) {}
            } message: {
                Text(backupErrorMessage)
            }
            .sheet(isPresented: $showingRestoreFilePicker) {
                BackupFilePickerView { url in
                    Task {
                        await restoreFromBackup(url: url)
                    }
                }
            }
            .sheet(isPresented: $showingImportView) {
                ImportView()
            }
            .task {
                await loadSettings()
            }
        }
    }

    // MARK: - Sections

    /// セキュリティセクション
    private var securitySection: some View {
        Section(header: Text(String(localized: "settings.security"))) {
            Toggle(isOn: Binding(
                get: { authService.isAuthenticationEnabled },
                set: { newValue in
                    Task {
                        let success = await authService.setAuthenticationEnabled(newValue)
                        if !success && newValue {
                            authErrorMessage = String(localized: "auth.notAvailable")
                            showingAuthError = true
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(authService.lockSettingLabel)
                    Text(String(localized: "settings.biometricLock.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// AI構造化セクション
    private var aiStructuringSection: some View {
        Section {
            NavigationLink {
                LLMSettingsView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "settings.aiStructuring"))

                        // 現在の設定状態を表示
                        Group {
                            if llmSettings.connectionMode == .none {
                                Text(String(localized: "llm.mode.none"))
                                    .foregroundStyle(.secondary)
                            } else if llmSettings.isAIStructuringEnabled {
                                Text("\(llmSettings.selectedProvider.displayName)")
                                    .foregroundStyle(.green)
                            } else {
                                Text(String(localized: "llm.apiKey.notSet"))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.caption)
                    }

                    Spacer()
                }
            }
        } header: {
            Text(String(localized: "settings.ai"))
        } footer: {
            Text(String(localized: "settings.aiStructuring.footer"))
        }
    }

    /// タグ管理セクション（Phase 2）
    private var tagManagementSection: some View {
        Section(header: Text(String(localized: "tag.management"))) {
            NavigationLink {
                TagListSettingsView()
            } label: {
                HStack {
                    Text(String(localized: "tag.management"))
                    Spacer()
                    Text("\(allTags.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// データ管理セクション
    private var dataManagementSection: some View {
        Section(header: Text(String(localized: "settings.dataManagement"))) {
            Button {
                showingImportView = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(.blue)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "settings.import"))
                            .foregroundStyle(.primary)
                        Text(String(localized: "settings.import.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// OCR設定セクション
    private var ocrSection: some View {
        Section(header: Text(String(localized: "settings.ocr"))) {
            NavigationLink {
                OCRLanguageSettingsView()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.ocrLanguages"))
                    Text(String(localized: "settings.ocrLanguages.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// バックアップセクション
    private var backupSection: some View {
        Section(header: Text(String(localized: "settings.backup"))) {
            // iCloudバックアップ
            Toggle(isOn: $iCloudBackupEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "backup.icloud.enabled"))
                    Text(String(localized: "backup.icloud"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: iCloudBackupEnabled) { _, newValue in
                Task {
                    await BackupService.shared.setAutoBackupEnabled(newValue)
                }
            }

            // 手動バックアップ
            Button {
                Task {
                    await createManualBackup()
                }
            } label: {
                HStack {
                    Text(String(localized: "settings.backup.manual"))
                    Spacer()
                    if isCreatingBackup {
                        ProgressView()
                    }
                }
            }
            .disabled(isCreatingBackup)

            // リストア
            Button {
                showingRestoreFilePicker = true
            } label: {
                HStack {
                    Text(String(localized: "settings.backup.restore"))
                    Spacer()
                    if isRestoring {
                        ProgressView()
                    }
                }
            }
            .disabled(isRestoring)
        }
    }

    /// このアプリについてセクション
    private var aboutSection: some View {
        Section(header: Text(String(localized: "settings.about"))) {
            HStack {
                Text(String(localized: "settings.version"))
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://akkurat.jp/privacy")!) {
                Text(String(localized: "settings.privacyPolicy"))
            }

            Link(destination: URL(string: "https://akkurat.jp/terms")!) {
                Text(String(localized: "settings.termsOfService"))
            }
        }
    }

    // MARK: - Computed Properties

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Methods

    private func loadSettings() async {
        iCloudBackupEnabled = await BackupService.shared.isAutoBackupEnabled
        // 旧設定からの移行を実行
        LLMSettingsManager.shared.migrateFromLegacySettings()
    }

    private func createManualBackup() async {
        isCreatingBackup = true
        defer { isCreatingBackup = false }

        do {
            _ = try await BackupService.shared.createBackup(modelContext: modelContext)
            showingBackupSuccess = true
        } catch {
            backupErrorMessage = error.localizedDescription
            showingBackupError = true
        }
    }

    private func restoreFromBackup(url: URL) async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await BackupService.shared.restoreBackup(from: url, modelContext: modelContext)
            showingRestoreSuccess = true
        } catch {
            backupErrorMessage = error.localizedDescription
            showingBackupError = true
        }
    }
}

// MARK: - AIDisclosureView

/// AI利用に関する説明画面。
struct AIDisclosureView: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // ヘッダー
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)

                        Text(String(localized: "ai.disclosure.title"))
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)

                    // 説明セクション
                    VStack(alignment: .leading, spacing: 16) {
                        disclosureSection(
                            icon: "doc.text.magnifyingglass",
                            title: String(localized: "ai.disclosure.what.title"),
                            description: String(localized: "ai.disclosure.what.description")
                        )

                        disclosureSection(
                            icon: "lock.shield",
                            title: String(localized: "ai.disclosure.privacy.title"),
                            description: String(localized: "ai.disclosure.privacy.description")
                        )

                        disclosureSection(
                            icon: "slider.horizontal.3",
                            title: String(localized: "ai.disclosure.modes.title"),
                            description: String(localized: "ai.disclosure.modes.description")
                        )

                        disclosureSection(
                            icon: "cloud.slash",
                            title: String(localized: "ai.disclosure.storage.title"),
                            description: String(localized: "ai.disclosure.storage.description")
                        )
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.ok")) {
                        onDismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func disclosureSection(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - TagListSettingsView

/// タグ一覧管理画面。
struct TagListSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var showingAddTag = false
    @State private var newTagName = ""
    @State private var newTagColor = "blue"
    @State private var editingTag: Tag?

    private let availableColors = ["blue", "green", "orange", "red", "purple", "pink", "yellow", "gray"]

    var body: some View {
        List {
            ForEach(tags) { tag in
                Button {
                    editingTag = tag
                    newTagName = tag.name
                    newTagColor = tag.color
                } label: {
                    HStack {
                        Circle()
                            .fill(colorForName(tag.color))
                            .frame(width: 12, height: 12)

                        Text(tag.name)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(tag.persons.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteTags)
        }
        .navigationTitle(String(localized: "tag.management"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newTagName = ""
                    newTagColor = "blue"
                    showingAddTag = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(String(localized: "tag.add"), isPresented: $showingAddTag) {
            TextField(String(localized: "tag.name"), text: $newTagName)
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "common.save")) {
                addTag()
            }
        }
        .alert(String(localized: "tag.edit"), isPresented: Binding(
            get: { editingTag != nil },
            set: { if !$0 { editingTag = nil } }
        )) {
            TextField(String(localized: "tag.name"), text: $newTagName)
            Button(String(localized: "common.cancel"), role: .cancel) {
                editingTag = nil
            }
            Button(String(localized: "common.save")) {
                updateTag()
            }
        }
    }

    private func addTag() {
        guard !newTagName.isEmpty else { return }
        let tag = Tag(name: newTagName, color: newTagColor)
        modelContext.insert(tag)
    }

    private func updateTag() {
        guard let tag = editingTag, !newTagName.isEmpty else { return }
        tag.name = newTagName
        tag.color = newTagColor
        editingTag = nil
    }

    private func deleteTags(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tags[index])
        }
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .blue
        }
    }
}

// MARK: - BackupFilePickerView

/// バックアップファイル選択画面。
struct BackupFilePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (URL) -> Void

    @State private var availableBackups: [URL] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if availableBackups.isEmpty {
                    ContentUnavailableView(
                        String(localized: "backup.noBackups"),
                        systemImage: "externaldrive.badge.xmark",
                        description: Text(String(localized: "backup.noBackups.description"))
                    )
                } else {
                    List(availableBackups, id: \.absoluteString) { url in
                        Button {
                            onSelect(url)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(url.lastPathComponent)
                                    .fontWeight(.medium)

                                if let date = fileDate(for: url) {
                                    Text(date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "settings.backup.restore"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadBackups()
            }
        }
    }

    private func loadBackups() async {
        availableBackups = await BackupService.shared.listAvailableBackups()
        isLoading = false
    }

    private func fileDate(for url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}

// MARK: - OCRLanguageSettingsView

/// OCR言語設定画面。
struct OCRLanguageSettingsView: View {
    @State private var selectedLanguages: Set<String> = ["ja", "en"]
    @State private var languageOrder: [String] = ["ja", "en", "zh-Hans", "zh-Hant", "ko"]

    private let availableLanguages: [(code: String, name: String)] = [
        ("ja", "日本語"),
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("ko", "한국어"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("es", "Español"),
        ("it", "Italiano"),
        ("pt", "Português"),
        ("ru", "Русский"),
        ("sv", "Svenska")
    ]

    var body: some View {
        List {
            Section {
                ForEach(availableLanguages, id: \.code) { language in
                    Toggle(language.name, isOn: Binding(
                        get: { selectedLanguages.contains(language.code) },
                        set: { isSelected in
                            if isSelected {
                                selectedLanguages.insert(language.code)
                            } else {
                                selectedLanguages.remove(language.code)
                            }
                        }
                    ))
                }
            } footer: {
                Text("選択した言語の順序でOCRが実行されます。上位の言語が優先されます。")
            }
        }
        .navigationTitle(String(localized: "settings.ocrLanguages"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AuthenticationService.shared)
}
