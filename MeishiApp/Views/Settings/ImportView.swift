import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Import View

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var importPhase: ImportPhase = .selectFormat
    @State private var selectedFormat: ImportFormat?
    @State private var isShowingFilePicker = false
    @State private var preview: ImportPreview?
    @State private var duplicateHandling: DuplicateHandling = .skip
    @State private var isImporting = false
    @State private var importResult: ImportResult?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch importPhase {
                case .selectFormat:
                    formatSelectionView
                case .preview:
                    previewView
                case .importing:
                    importingView
                case .result:
                    resultView
                }
            }
            .navigationTitle(String(localized: "import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingFilePicker,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert(String(localized: "error.generic"), isPresented: .constant(errorMessage != nil)) {
                Button(String(localized: "common.ok")) {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Format Selection View

    private var formatSelectionView: some View {
        List {
            Section {
                Button {
                    selectedFormat = .csv
                    isShowingFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: "tablecells")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "import.csv"))
                                .font(.headline)
                            Text(String(localized: "import.csv.description"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    selectedFormat = .vcard
                    isShowingFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.title2)
                            .foregroundStyle(.green)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "import.vcard"))
                                .font(.headline)
                            Text(String(localized: "import.vcard.description"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text(String(localized: "import.selectFormat"))
            }
        }
    }

    // MARK: - Preview View

    private var previewView: some View {
        List {
            if let preview = preview {
                Section {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.blue)
                        Text(String(localized: "import.preview.found \(preview.totalCount)"))
                    }

                    if preview.duplicateCount > 0 {
                        HStack {
                            Image(systemName: "person.2")
                                .foregroundStyle(.orange)
                            Text(String(localized: "import.preview.duplicates \(preview.duplicateCount)"))
                        }
                    }
                } header: {
                    Text(String(localized: "import.preview.title"))
                }

                Section {
                    Text(String(localized: "import.preview.textOnly"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if preview.duplicateCount > 0 {
                    Section {
                        Picker(String(localized: "import.duplicateHandling"), selection: $duplicateHandling) {
                            Text(String(localized: "import.duplicateHandling.skip"))
                                .tag(DuplicateHandling.skip)
                            Text(String(localized: "import.duplicateHandling.addCard"))
                                .tag(DuplicateHandling.addCard)
                        }
                    } header: {
                        Text(String(localized: "import.duplicateHandling"))
                    }
                }

                Section {
                    ForEach(preview.entries.prefix(10)) { entry in
                        entryRow(entry)
                    }

                    if preview.entries.count > 10 {
                        Text(String(localized: "import.preview.andMore \(preview.entries.count - 10)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String(localized: "import.preview.entries"))
                }

                Section {
                    Button {
                        executeImport()
                    } label: {
                        HStack {
                            Spacer()
                            Text(String(localized: "import.execute"))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: ImportEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name.isEmpty ? (entry.company ?? "") : entry.name)
                    .font(.headline)

                if !entry.name.isEmpty, let company = entry.company {
                    Text(company)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if entry.isDuplicate {
                Text(String(localized: "import.duplicate"))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Importing View

    private var importingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(String(localized: "import.processing"))
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result View

    private var resultView: some View {
        List {
            if let result = importResult {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title)
                        Text(String(localized: "import.result.title"))
                            .font(.headline)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    if result.importedCount > 0 {
                        Label {
                            Text(String(localized: "import.result.imported \(result.importedCount)"))
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    if result.duplicateCount > 0 {
                        Label {
                            Text(String(localized: "import.result.duplicates \(result.duplicateCount)"))
                        } icon: {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(.orange)
                        }
                    }

                    if result.skippedCount > 0 {
                        Label {
                            Text(String(localized: "import.result.skipped \(result.skippedCount)"))
                        } icon: {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(.gray)
                        }
                    }

                    if !result.errors.isEmpty {
                        Label {
                            Text(String(localized: "import.result.errors \(result.errors.count)"))
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                if !result.errors.isEmpty {
                    Section {
                        ForEach(result.errors) { error in
                            VStack(alignment: .leading, spacing: 4) {
                                if let name = error.name {
                                    Text(name)
                                        .font(.headline)
                                }
                                Text(error.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(String(localized: "import.result.errorDetails"))
                    }
                }

                Section {
                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text(String(localized: "common.done"))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var allowedContentTypes: [UTType] {
        switch selectedFormat {
        case .csv:
            return [.commaSeparatedText, .plainText]
        case .vcard:
            return [.vCard]
        case .none:
            return [.commaSeparatedText, .vCard]
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadPreview(from: url)

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func loadPreview(from url: URL) {
        do {
            switch selectedFormat {
            case .csv:
                preview = try ImportService.shared.previewCSV(from: url, modelContext: modelContext)
            case .vcard:
                preview = try ImportService.shared.previewVCard(from: url, modelContext: modelContext)
            case .none:
                return
            }
            importPhase = .preview
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func executeImport() {
        guard let preview = preview, let format = selectedFormat else { return }

        importPhase = .importing
        isImporting = true

        // ファイルURLを再取得する必要があるため、プレビューのエントリから直接インポート
        // 実際の実装ではファイルURLを保持する
        Task {
            // シミュレートされた遅延
            try? await Task.sleep(nanoseconds: 500_000_000)

            await MainActor.run {
                // プレビューからインポート結果を作成
                var importedCount = 0
                var duplicateCount = 0

                let descriptor = FetchDescriptor<Person>()
                let existingPersons = (try? modelContext.fetch(descriptor)) ?? []

                for entry in preview.entries {
                    if entry.isDuplicate {
                        duplicateCount += 1
                        switch duplicateHandling {
                        case .skip:
                            continue
                        case .addCard:
                            if let personId = entry.duplicatePersonId,
                               let person = existingPersons.first(where: { $0.id == personId }) {
                                let card = createBusinessCard(from: entry)
                                person.businessCards.append(card)
                                importedCount += 1
                            }
                        }
                    } else {
                        let person = createPerson(from: entry)
                        modelContext.insert(person)
                        importedCount += 1
                    }
                }

                try? modelContext.save()

                importResult = ImportResult(
                    totalCount: preview.totalCount,
                    importedCount: importedCount,
                    duplicateCount: duplicateCount,
                    skippedCount: duplicateHandling == .skip ? duplicateCount : 0,
                    errors: []
                )

                isImporting = false
                importPhase = .result
            }
        }
    }

    private func createPerson(from entry: ImportEntry) -> Person {
        let person = Person(
            name: entry.name,
            nameReading: entry.nameReading,
            primaryCompany: entry.company,
            primaryTitle: entry.title
        )

        let card = createBusinessCard(from: entry)
        person.businessCards.append(card)

        return person
    }

    private func createBusinessCard(from entry: ImportEntry) -> BusinessCard {
        let card = BusinessCard()
        card.company = entry.company
        card.department = entry.department
        card.title = entry.title
        card.phoneNumbers = entry.phoneNumbers
        card.emails = entry.emails
        card.address = entry.address
        card.websites = entry.websites
        card.memo = entry.memo
        card.acquiredAt = Date()
        return card
    }
}

// MARK: - Types

private enum ImportPhase {
    case selectFormat
    case preview
    case importing
    case result
}

enum ImportFormat {
    case csv
    case vcard
}

// MARK: - Preview

#Preview {
    ImportView()
        .modelContainer(for: Person.self, inMemory: true)
}
