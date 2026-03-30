import SwiftUI
import SwiftData

// MARK: - PersonListView

/// 人の一覧を表示するメインビュー。
/// リスト表示、グリッド表示、名刺サムネイル表示を切り替え可能。
struct PersonListView: View {
    // MARK: - Types

    enum DisplayMode: String, CaseIterable {
        case list
        case faceGrid
        case cardThumbnail

        var iconName: String {
            switch self {
            case .list:
                return "list.bullet"
            case .faceGrid:
                return "square.grid.2x2"
            case .cardThumbnail:
                return "rectangle.grid.2x2"
            }
        }

        var localizedName: String {
            switch self {
            case .list:
                return "リスト"
            case .faceGrid:
                return "顔写真"
            case .cardThumbnail:
                return "名刺"
            }
        }
    }

    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.updatedAt, order: .reverse) private var persons: [Person]

    @State private var searchText = ""
    @State private var selectedSortOption: SortOption = .recent
    @State private var displayMode: DisplayMode = .list
    @State private var showingAddCard = false
    @State private var selectedTagFilter: Tag?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if persons.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .navigationTitle(String(localized: "person.list.title"))
            .searchable(text: $searchText, prompt: String(localized: "common.search"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    displayModeMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        tagFilterMenu
                        sortMenu
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                addButton
            }
            .sheet(isPresented: $showingAddCard) {
                CardCaptureView()
            }
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch displayMode {
        case .list:
            personListContent
        case .faceGrid:
            faceGridContent
        case .cardThumbnail:
            cardThumbnailContent
        }
    }

    // MARK: - Subviews

    /// 空状態の表示
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(
                String(localized: "person.list.empty"),
                systemImage: "person.text.rectangle"
            )
        } description: {
            Text(String(localized: "person.list.empty.hint"))
        }
    }

    /// 人のリスト
    private var personListContent: some View {
        List {
            ForEach(filteredPersons) { person in
                NavigationLink(destination: PersonDetailView(person: person)) {
                    PersonRowView(person: person)
                }
            }
            .onDelete(perform: deletePersons)
        }
        .listStyle(.plain)
    }

    /// 顔写真グリッド
    private var faceGridContent: some View {
        ScrollView {
            let personsWithFace = filteredPersons.filter { $0.hasFacePhoto }

            if personsWithFace.isEmpty {
                ContentUnavailableView {
                    Label("顔写真がありません", systemImage: "person.crop.circle")
                } description: {
                    Text("人の詳細画面から顔写真を追加してください")
                }
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)
                ], spacing: 16) {
                    ForEach(personsWithFace) { person in
                        NavigationLink(destination: PersonDetailView(person: person)) {
                            FaceGridCell(person: person)
                        }
                    }
                }
                .padding()
            }
        }
    }

    /// 名刺サムネイルグリッド
    private var cardThumbnailContent: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
            ], spacing: 12) {
                ForEach(filteredPersons) { person in
                    NavigationLink(destination: PersonDetailView(person: person)) {
                        CardThumbnailCell(person: person)
                    }
                }
            }
            .padding()
        }
    }

    /// 表示モードメニュー
    private var displayModeMenu: some View {
        Menu {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                Button {
                    displayMode = mode
                } label: {
                    HStack {
                        Image(systemName: mode.iconName)
                        Text(mode.localizedName)
                        if displayMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: displayMode.iconName)
        }
    }

    /// タグフィルタメニュー
    private var tagFilterMenu: some View {
        Menu {
            Button {
                selectedTagFilter = nil
            } label: {
                HStack {
                    Text(String(localized: "tag.all"))
                    if selectedTagFilter == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(allTags) { tag in
                Button {
                    selectedTagFilter = tag
                } label: {
                    HStack {
                        Text(tag.name)
                        if selectedTagFilter?.id == tag.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: selectedTagFilter != nil ? "tag.fill" : "tag")
        }
    }

    /// ソートメニュー
    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    selectedSortOption = option
                } label: {
                    HStack {
                        Text(option.localizedName)
                        if selectedSortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    /// 追加ボタン
    private var addButton: some View {
        Button {
            showingAddCard = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .padding()
        .accessibilityLabel(String(localized: "card.add"))
    }

    // MARK: - Computed Properties

    /// すべてのタグ
    private var allTags: [Tag] {
        var tags: Set<Tag> = []
        for person in persons {
            tags.formUnion(person.tags)
        }
        return Array(tags).sorted { $0.name < $1.name }
    }

    /// 検索・ソート・フィルタ済みの人リスト
    private var filteredPersons: [Person] {
        var result = persons

        // タグフィルタ
        if let tagFilter = selectedTagFilter {
            result = result.filter { person in
                person.tags.contains { $0.id == tagFilter.id }
            }
        }

        // 検索フィルタ
        if !searchText.isEmpty {
            result = result.filter { person in
                person.name.localizedCaseInsensitiveContains(searchText) ||
                (person.primaryCompany?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (person.primaryTitle?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (person.memo?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                person.tags.contains { $0.name.localizedCaseInsensitiveContains(searchText) } ||
                person.encounters.contains { encounter in
                    encounter.eventName?.localizedCaseInsensitiveContains(searchText) ?? false
                }
            }
        }

        // ソート
        switch selectedSortOption {
        case .recent:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .name:
            result.sort { $0.name < $1.name }
        case .company:
            result.sort { ($0.primaryCompany ?? "") < ($1.primaryCompany ?? "") }
        }

        return result
    }

    // MARK: - Methods

    /// 人を削除
    private func deletePersons(at offsets: IndexSet) {
        for index in offsets {
            let person = filteredPersons[index]
            modelContext.delete(person)
        }
    }
}

// MARK: - SortOption

enum SortOption: CaseIterable {
    case recent
    case name
    case company

    var localizedName: String {
        switch self {
        case .recent:
            return String(localized: "person.sort.recent")
        case .name:
            return String(localized: "person.sort.name")
        case .company:
            return String(localized: "person.sort.company")
        }
    }
}

// MARK: - PersonRowView

/// 人の一覧の1行を表示するビュー。
struct PersonRowView: View {
    // MARK: - Properties

    let person: Person
    @State private var faceImage: UIImage?

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // 顔写真 or イニシャル
            avatarView
                .frame(width: 50, height: 50)

            // 名前・会社名・役職
            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.headline)

                if let company = person.primaryCompany, !company.isEmpty {
                    Text(company)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let title = person.primaryTitle, !title.isEmpty {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // タグ表示（最初の1つ）
            if let firstTag = person.tags.first {
                Text(firstTag.name)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }

            // 名刺枚数バッジ
            if person.businessCardCount > 1 {
                Text("\(person.businessCardCount)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .task {
            await loadFaceImage()
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
                    Text(person.initials)
                        .font(.headline)
                        .foregroundStyle(.gray)
                }
        }
    }

    // MARK: - Methods

    private func loadFaceImage() async {
        guard let path = person.facePhotoPath else { return }
        faceImage = await ImageStorageService.shared.loadImage(relativePath: path)
    }
}

// MARK: - FaceGridCell

/// 顔写真グリッドの1セル。
struct FaceGridCell: View {
    let person: Person
    @State private var faceImage: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            if let faceImage = faceImage {
                Image(uiImage: faceImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Text(person.initials)
                            .font(.title2)
                            .foregroundStyle(.gray)
                    }
            }

            Text(person.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .task {
            if let path = person.facePhotoPath {
                faceImage = await ImageStorageService.shared.loadImage(relativePath: path)
            }
        }
    }
}

// MARK: - CardThumbnailCell

/// 名刺サムネイルグリッドの1セル。
struct CardThumbnailCell: View {
    let person: Person
    @State private var cardImage: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            if let cardImage = cardImage {
                Image(uiImage: cardImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 90)
                    .overlay {
                        Image(systemName: "rectangle.portrait")
                            .foregroundStyle(.gray)
                    }
            }

            VStack(spacing: 2) {
                Text(person.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let company = person.primaryCompany {
                    Text(company)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            if let latestCard = person.latestBusinessCard {
                cardImage = await ImageStorageService.shared.loadImage(relativePath: latestCard.frontImagePath)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PersonListView()
        .modelContainer(for: [Person.self, BusinessCard.self, Encounter.self, Tag.self], inMemory: true)
}
