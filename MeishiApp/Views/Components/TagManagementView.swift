import SwiftUI
import SwiftData

// MARK: - TagManagementView

/// タグの作成・管理画面。
struct TagManagementView: View {
    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @Bindable var person: Person

    @State private var showingCreateTag = false
    @State private var newTagName = ""
    @State private var tagToDelete: Tag?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // 現在のタグ
                if !person.tags.isEmpty {
                    Section(header: Text("現在のタグ")) {
                        ForEach(person.tags) { tag in
                            HStack {
                                Text(tag.name)
                                Spacer()
                                Button {
                                    removeTag(tag)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }

                // 利用可能なタグ
                Section(header: Text("タグを追加")) {
                    let availableTags = allTags.filter { tag in
                        !person.tags.contains { $0.id == tag.id }
                    }

                    if availableTags.isEmpty && allTags.isEmpty {
                        Text("タグがまだありません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableTags) { tag in
                            Button {
                                addTag(tag)
                            } label: {
                                HStack {
                                    Text(tag.name)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .foregroundStyle(.primary)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    tagToDelete = tag
                                } label: {
                                    Label(String(localized: "common.delete"), systemImage: "trash")
                                }
                            }
                        }
                    }

                    // 新しいタグを作成
                    Button {
                        showingCreateTag = true
                    } label: {
                        Label(String(localized: "tag.create"), systemImage: "plus")
                    }
                }
            }
            .navigationTitle(String(localized: "tag.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) {
                        dismiss()
                    }
                }
            }
            .alert(String(localized: "tag.create"), isPresented: $showingCreateTag) {
                TextField(String(localized: "tag.name.placeholder"), text: $newTagName)
                Button(String(localized: "common.cancel"), role: .cancel) {
                    newTagName = ""
                }
                Button(String(localized: "common.add")) {
                    createAndAddTag()
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .confirmationDialog(
                "タグを削除",
                isPresented: .init(
                    get: { tagToDelete != nil },
                    set: { if !$0 { tagToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    if let tag = tagToDelete {
                        deleteTag(tag)
                    }
                }
            } message: {
                if let tag = tagToDelete {
                    Text("タグ「\(tag.name)」を削除しますか？このタグが付いている全員から削除されます。")
                }
            }
        }
    }

    // MARK: - Methods

    private func addTag(_ tag: Tag) {
        person.addTag(tag)
    }

    private func removeTag(_ tag: Tag) {
        person.removeTag(tag)
    }

    private func createAndAddTag() {
        let trimmedName = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // 既存のタグをチェック
        if let existingTag = allTags.first(where: { $0.name == trimmedName }) {
            addTag(existingTag)
        } else {
            // 新しいタグを作成
            let newTag = Tag(name: trimmedName)
            modelContext.insert(newTag)
            addTag(newTag)
        }

        newTagName = ""
    }

    private func deleteTag(_ tag: Tag) {
        modelContext.delete(tag)
        tagToDelete = nil
    }
}

// MARK: - TagSelectionRow

/// PersonDetail画面のタグセクションに表示する行。
struct TagSelectionRow: View {
    @Bindable var person: Person
    @State private var showingTagManagement = false

    var body: some View {
        Button {
            showingTagManagement = true
        } label: {
            HStack {
                if person.tags.isEmpty {
                    Text(String(localized: "tag.add"))
                        .foregroundStyle(.blue)
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
        .sheet(isPresented: $showingTagManagement) {
            TagManagementView(person: person)
        }
    }
}

// MARK: - TagListView

/// 全タグの管理画面（設定画面から遷移）。
struct TagListView: View {
    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var showingCreateTag = false
    @State private var newTagName = ""
    @State private var tagToEdit: Tag?
    @State private var editedTagName = ""

    // MARK: - Body

    var body: some View {
        List {
            if tags.isEmpty {
                ContentUnavailableView {
                    Label("タグがありません", systemImage: "tag")
                } description: {
                    Text("名刺を整理するためのタグを作成してください")
                }
            } else {
                ForEach(tags) { tag in
                    HStack {
                        Text(tag.name)
                        Spacer()
                        Text("\(tag.personCount)人")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteTag(tag)
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }

                        Button {
                            tagToEdit = tag
                            editedTagName = tag.name
                        } label: {
                            Label(String(localized: "common.edit"), systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .navigationTitle("タグ管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateTag = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(String(localized: "tag.create"), isPresented: $showingCreateTag) {
            TextField(String(localized: "tag.name.placeholder"), text: $newTagName)
            Button(String(localized: "common.cancel"), role: .cancel) {
                newTagName = ""
            }
            Button(String(localized: "common.add")) {
                createTag()
            }
            .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .alert("タグを編集", isPresented: .init(
            get: { tagToEdit != nil },
            set: { if !$0 { tagToEdit = nil } }
        )) {
            TextField("タグ名", text: $editedTagName)
            Button(String(localized: "common.cancel"), role: .cancel) {
                tagToEdit = nil
            }
            Button(String(localized: "common.save")) {
                updateTag()
            }
            .disabled(editedTagName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Methods

    private func createTag() {
        let trimmedName = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // 重複チェック
        guard !tags.contains(where: { $0.name == trimmedName }) else {
            newTagName = ""
            return
        }

        let tag = Tag(name: trimmedName)
        modelContext.insert(tag)
        newTagName = ""
    }

    private func updateTag() {
        guard let tag = tagToEdit else { return }
        let trimmedName = editedTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        tag.name = trimmedName
        tagToEdit = nil
    }

    private func deleteTag(_ tag: Tag) {
        modelContext.delete(tag)
    }
}

// MARK: - Preview

#Preview {
    TagManagementView(person: Person(name: "山田太郎"))
        .modelContainer(for: [Person.self, Tag.self], inMemory: true)
}
