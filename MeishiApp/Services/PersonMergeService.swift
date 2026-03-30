import Foundation
import SwiftData
import os.log

// MARK: - PersonMergeService

/// 2つのPersonを統合するサービス。
/// sourceをtargetに統合し、sourceは削除される。
final class PersonMergeService {
    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "PersonMerge")

    // MARK: - Singleton

    static let shared = PersonMergeService()

    private init() {}

    // MARK: - Public Methods

    /// 2つのPersonを統合する
    /// - Parameters:
    ///   - source: 統合元（統合後に削除される）
    ///   - target: 統合先（統合後も残る）
    ///   - preferredName: ユーザーが選んだ表示名
    ///   - preferredNameReading: ユーザーが選んだふりがな（オプション）
    ///   - preferredFacePhotoPath: ユーザーが選んだ顔写真パス（nilなら既存を維持）
    ///   - useSourceInfo: sourceの会社名・役職を使用するかどうか
    ///   - modelContext: SwiftData ModelContext
    func merge(
        source: Person,
        into target: Person,
        preferredName: String,
        preferredNameReading: String? = nil,
        preferredFacePhotoPath: String?,
        useSourceInfo: Bool = false,
        modelContext: ModelContext
    ) {
        logger.info("Merging Person '\(source.name)' into '\(target.name)'")

        // 1. sourceのBusinessCardをすべてtargetに移動
        moveBusinessCards(from: source, to: target)

        // 2. sourceのEncounterをすべてtargetに移動
        moveEncounters(from: source, to: target)

        // 3. タグを合算（重複除外）
        mergeTags(from: source, to: target)

        // 4. メモの統合
        mergeMemos(from: source, to: target)

        // 5. targetのname, nameReading, facePhotoPathを更新
        target.name = preferredName
        if let reading = preferredNameReading {
            target.nameReading = reading
        } else if source.name == preferredName {
            // sourceの名前を選択した場合、sourceのふりがなを使用
            target.nameReading = source.nameReading ?? target.nameReading
        }

        if let photoPath = preferredFacePhotoPath {
            // 古い顔写真を削除（選択されなかった方）
            if photoPath == source.facePhotoPath, let oldPath = target.facePhotoPath {
                deleteOldFacePhoto(path: oldPath)
            } else if photoPath == target.facePhotoPath, let oldPath = source.facePhotoPath {
                deleteOldFacePhoto(path: oldPath)
            }
            target.facePhotoPath = photoPath
        } else if target.facePhotoPath == nil, let sourcePath = source.facePhotoPath {
            // targetに顔写真がなく、sourceにある場合は引き継ぐ
            target.facePhotoPath = sourcePath
        } else if let sourcePath = source.facePhotoPath, sourcePath != target.facePhotoPath {
            // sourceの顔写真は使わないので削除
            deleteOldFacePhoto(path: sourcePath)
        }

        // 6. primaryCompany, primaryTitleを設定
        // ユーザーがsourceの情報を選んだ場合はsourceの会社名・役職を使用
        if useSourceInfo {
            target.primaryCompany = source.primaryCompany
            target.primaryTitle = source.primaryTitle
        }
        // targetの情報を選んだ場合は、既存のprimaryCompany/primaryTitleをそのまま維持
        // （何もしない）

        // 7. updatedAtを更新
        target.updatedAt = Date()

        // 8. sourceを削除（BusinessCardとEncounterはtargetに移動済みなのでcascade削除されない）
        // sourceのtagsからsourceを除去
        for tag in source.tags {
            tag.persons.removeAll { $0.id == source.id }
        }
        source.tags.removeAll()
        source.businessCards.removeAll()
        source.encounters.removeAll()

        modelContext.delete(source)

        logger.info("Merge completed successfully")
    }

    // MARK: - Private Methods

    /// BusinessCardを移動
    private func moveBusinessCards(from source: Person, to target: Person) {
        let cards = source.businessCards
        for card in cards {
            card.person = target
            target.businessCards.append(card)
        }
        source.businessCards.removeAll()
        logger.debug("Moved \(cards.count) business cards")
    }

    /// Encounterを移動
    private func moveEncounters(from source: Person, to target: Person) {
        let encounters = source.encounters
        for encounter in encounters {
            encounter.person = target
            target.encounters.append(encounter)
        }
        source.encounters.removeAll()
        logger.debug("Moved \(encounters.count) encounters")
    }

    /// タグを合算
    private func mergeTags(from source: Person, to target: Person) {
        for tag in source.tags {
            // targetに同じタグがなければ追加
            if !target.tags.contains(where: { $0.id == tag.id }) {
                target.tags.append(tag)
                tag.persons.append(target)
            }
            // sourceからタグを除去
            tag.persons.removeAll { $0.id == source.id }
        }
        source.tags.removeAll()
        logger.debug("Merged tags")
    }

    /// メモを統合
    private func mergeMemos(from source: Person, to target: Person) {
        let sourceMemo = source.memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetMemo = target.memo?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (targetMemo, sourceMemo) {
        case (nil, let sourceMemo?):
            // targetにメモがなく、sourceにある
            target.memo = sourceMemo
        case (let targetMemo?, let sourceMemo?) where !sourceMemo.isEmpty:
            // 両方にメモがある
            target.memo = "\(targetMemo)\n\n---\n\n\(sourceMemo)"
        default:
            // targetのメモをそのまま維持
            break
        }
        logger.debug("Merged memos")
    }

    /// 古い顔写真を削除
    private func deleteOldFacePhoto(path: String) {
        Task {
            await ImageStorageService.shared.deleteImage(relativePath: path)
        }
    }

    // MARK: - Preview Methods

    /// 統合後のタグ一覧を取得（プレビュー用）
    func mergedTags(source: Person, target: Person) -> [Tag] {
        var tags = target.tags
        for tag in source.tags {
            if !tags.contains(where: { $0.id == tag.id }) {
                tags.append(tag)
            }
        }
        return tags.sorted { $0.name < $1.name }
    }

    /// 統合後の名刺数を取得（プレビュー用）
    func mergedCardCount(source: Person, target: Person) -> Int {
        source.businessCardCount + target.businessCardCount
    }

    /// 統合後のEncounter数を取得（プレビュー用）
    func mergedEncounterCount(source: Person, target: Person) -> Int {
        source.encounterCount + target.encounterCount
    }
}
