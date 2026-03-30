import SwiftUI
import SwiftData

// MARK: - PersonMergeView

/// Person統合機能のメインビュー。
/// 統合先の選択と確認画面を提供する。
struct PersonMergeView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// 統合元のPerson（このPersonが統合後に削除される）
    let sourcePerson: Person

    /// 統合先候補のPerson一覧（sourcePerson以外）
    let allPersons: [Person]

    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var isLoaded = false

    // MARK: - Computed Properties

    private var filteredPersons: [Person] {
        guard isLoaded else { return [] }

        if searchText.isEmpty {
            return allPersons
        }

        let lowercasedSearch = searchText.lowercased()
        return allPersons.filter { person in
            person.name.lowercased().contains(lowercasedSearch) ||
            (person.nameReading?.lowercased().contains(lowercasedSearch) ?? false) ||
            (person.primaryCompany?.lowercased().contains(lowercasedSearch) ?? false)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if isLoaded {
                    listContent
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "person.merge.selectTarget"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: Person.self) { target in
                PersonMergeConfirmationView(
                    source: sourcePerson,
                    target: target,
                    onMergeComplete: {
                        dismiss()
                    }
                )
            }
            .onAppear {
                // 少し遅延させて表示
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isLoaded = true
                }
            }
        }
    }

    // MARK: - Views

    private var listContent: some View {
        VStack(spacing: 0) {
            // 常に表示される検索バー
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "person.merge.searchPlaceholder"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 人数表示
            HStack {
                Text(String(localized: "person.merge.resultCount \(filteredPersons.count)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 4)

            // リスト
            List {
                ForEach(filteredPersons) { person in
                    Button {
                        navigationPath.append(person)
                    } label: {
                        SimpleMergePersonRow(person: person)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
        .overlay {
            if filteredPersons.isEmpty && !searchText.isEmpty {
                ContentUnavailableView(
                    String(localized: "person.merge.noResults"),
                    systemImage: "magnifyingglass",
                    description: Text(String(localized: "person.merge.noResults.description"))
                )
            } else if filteredPersons.isEmpty {
                ContentUnavailableView(
                    String(localized: "person.list.empty"),
                    systemImage: "person.crop.rectangle.badge.plus"
                )
            }
        }
    }
}

// MARK: - SimpleMergePersonRow

/// シンプルなPerson行ビュー（画像読み込みなし）。
struct SimpleMergePersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 12) {
            // イニシャルのみ表示
            Text(person.initials)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Color.blue.opacity(0.7))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.headline)

                if let company = person.primaryCompany {
                    Text(company)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Label("\(person.businessCardCount)", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    Label("\(person.encounterCount)", systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - PersonMergeConfirmationView

/// Person統合の確認画面。
struct PersonMergeConfirmationView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let source: Person
    let target: Person
    let onMergeComplete: () -> Void

    @State private var selectedName: String
    @State private var selectedNameReading: String?
    @State private var selectedPhotoPath: String?
    @State private var isMerging = false
    @State private var showingSuccess = false
    @State private var isViewReady = false

    @State private var sourceFaceImage: UIImage?
    @State private var targetFaceImage: UIImage?
    @State private var mergedTags: [Tag] = []

    // MARK: - Initialization

    init(source: Person, target: Person, onMergeComplete: @escaping () -> Void) {
        self.source = source
        self.target = target
        self.onMergeComplete = onMergeComplete

        // デフォルトは新しい方（target）の名前
        _selectedName = State(initialValue: target.name)
        _selectedNameReading = State(initialValue: target.nameReading)
        _selectedPhotoPath = State(initialValue: target.facePhotoPath ?? source.facePhotoPath)

    }

    // MARK: - Computed Properties

    private var mergedCardCount: Int {
        source.businessCardCount + target.businessCardCount
    }

    private var mergedEncounterCount: Int {
        source.encounterCount + target.encounterCount
    }

    private var bothHaveFacePhotos: Bool {
        source.hasFacePhoto && target.hasFacePhoto
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isViewReady {
                confirmationContent
            } else {
                ProgressView("読み込み中...")
            }
        }
        .navigationTitle(String(localized: "person.merge.confirm.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 遅延して表示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isViewReady = true
            }
        }
        .alert(String(localized: "person.merge.success"), isPresented: $showingSuccess) {
            Button(String(localized: "common.ok")) {
                dismiss()
                onMergeComplete()
            }
        }
    }

    // MARK: - Content

    private var confirmationContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 2人の比較表示
                comparisonSection

                Divider()

                // 表示名の選択
                nameSelectionSection

                // 顔写真の選択（両方にある場合のみ）
                if bothHaveFacePhotos {
                    Divider()
                    photoSelectionSection
                }

                Divider()

                // 統合プレビュー
                previewSection

                // 警告
                warningSection

                // 統合ボタン
                mergeButton
            }
            .padding()
        }
        .task {
            // タグをロード
            mergedTags = PersonMergeService.shared.mergedTags(source: source, target: target)
            // 顔写真をロード
            await loadFaceImages()
        }
    }

    // MARK: - Sections

    /// 2人の比較表示セクション
    private var comparisonSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // Source Person
            personCard(
                person: source,
                faceImage: sourceFaceImage,
                label: String(localized: "person.merge.source")
            )

            Image(systemName: "arrow.right")
                .font(.title2)
                .foregroundStyle(.secondary)
                .padding(.top, 40)

            // Target Person
            personCard(
                person: target,
                faceImage: targetFaceImage,
                label: String(localized: "person.merge.target")
            )
        }
    }

    /// Person情報カード
    private func personCard(person: Person, faceImage: UIImage?, label: String) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            // 顔写真またはイニシャル
            Group {
                if let image = faceImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(person.initials)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.blue.opacity(0.7))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())

            Text(person.name)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let company = person.primaryCompany {
                Text(company)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 4) {
                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                Text("\(person.businessCardCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// 表示名選択セクション
    private var nameSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "person.merge.selectName"))
                .font(.headline)

            VStack(spacing: 8) {
                nameOptionButton(person: target)
                if source.name != target.name {
                    nameOptionButton(person: source)
                }
            }
        }
    }

    /// 名前選択ボタン（会社名・役職も表示）
    private func nameOptionButton(person: Person) -> some View {
        let isSelected = selectedName == person.name
        return Button {
            selectedName = person.name
            selectedNameReading = person.nameReading
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .foregroundStyle(.primary)
                    if let reading = person.nameReading, !reading.isEmpty {
                        Text(reading)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // 会社名・役職を表示（選択時にどの情報が使われるかわかりやすくする）
                    if let company = person.primaryCompany {
                        HStack(spacing: 4) {
                            Text(company)
                            if let title = person.primaryTitle {
                                Text("・")
                                Text(title)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    /// 顔写真選択セクション
    private var photoSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "person.merge.selectPhoto"))
                .font(.headline)

            HStack(spacing: 16) {
                if let image = targetFaceImage, let path = target.facePhotoPath {
                    photoOptionButton(image: image, path: path)
                }
                if let image = sourceFaceImage, let path = source.facePhotoPath {
                    photoOptionButton(image: image, path: path)
                }
            }
        }
    }

    /// 顔写真選択ボタン
    private func photoOptionButton(image: UIImage, path: String) -> some View {
        Button {
            selectedPhotoPath = path
        } label: {
            VStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(selectedPhotoPath == path ? Color.blue : Color.clear, lineWidth: 3)
                    }

                Image(systemName: selectedPhotoPath == path ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedPhotoPath == path ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// 統合プレビューセクション
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "person.merge.preview"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                // 名刺数
                previewRow(
                    text: String(
                        localized: "person.merge.preview.cards \(source.businessCardCount) \(target.businessCardCount) \(mergedCardCount)"
                    )
                )

                // Encounter数
                previewRow(
                    text: String(
                        localized: "person.merge.preview.encounters \(source.encounterCount) \(target.encounterCount) \(mergedEncounterCount)"
                    )
                )

                // タグ
                if !mergedTags.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "tag")
                            .foregroundStyle(.secondary)
                        MergeFlowLayout(spacing: 4) {
                            ForEach(mergedTags) { tag in
                                Text(tag.name)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// プレビュー行
    private func previewRow(text: String) -> some View {
        HStack {
            Image(systemName: "checkmark")
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline)
        }
    }

    /// 警告セクション
    private var warningSection: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(String(localized: "person.merge.warning"))
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// 統合ボタン
    private var mergeButton: some View {
        Button {
            executeMerge()
        } label: {
            HStack {
                if isMerging {
                    ProgressView()
                        .padding(.trailing, 4)
                }
                Text(String(localized: "person.merge.execute"))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(isMerging)
    }

    // MARK: - Methods

    private func loadFaceImages() async {
        if let path = source.facePhotoPath {
            sourceFaceImage = await ImageStorageService.shared.loadImage(relativePath: path)
        }
        if let path = target.facePhotoPath {
            targetFaceImage = await ImageStorageService.shared.loadImage(relativePath: path)
        }
    }

    private func executeMerge() {
        isMerging = true

        // ユーザーがsourceの名前を選択した場合、sourceの会社名・役職を使用
        let useSourceInfo = (selectedName == source.name)

        PersonMergeService.shared.merge(
            source: source,
            into: target,
            preferredName: selectedName,
            preferredNameReading: selectedNameReading,
            preferredFacePhotoPath: selectedPhotoPath,
            useSourceInfo: useSourceInfo,
            modelContext: modelContext
        )

        isMerging = false
        showingSuccess = true
    }
}

// MARK: - MergeFlowLayout

/// タグを折り返し表示するためのFlowLayout（統合画面用）。
struct MergeFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth, x > 0 {
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

// MARK: - Preview

#Preview {
    let person1 = Person(name: "山田太郎", primaryCompany: "株式会社サンプル")
    let person2 = Person(name: "田中花子", primaryCompany: "テスト株式会社")

    return PersonMergeConfirmationView(
        source: person1,
        target: person2,
        onMergeComplete: {}
    )
}
