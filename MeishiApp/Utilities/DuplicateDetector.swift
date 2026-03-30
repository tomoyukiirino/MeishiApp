import Foundation
import SwiftData
import os.log

// MARK: - DuplicateDetector

/// 重複検出ユーティリティ。
/// OCR/構造化で氏名・会社名が確定した時点でSwiftDataのPersonを検索し、
/// 既存の人と一致するかを判定する。
final class DuplicateDetector {
    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "DuplicateDetector")
    private let modelContext: ModelContext

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    /// 重複候補を検出
    /// - Parameters:
    ///   - name: 氏名
    ///   - company: 会社名
    ///   - email: メールアドレス
    /// - Returns: 一致する可能性のあるPersonのリスト（スコア順）
    func findDuplicates(
        name: String?,
        company: String?,
        email: String?
    ) -> [DuplicateCandidate] {
        logger.info("Searching for duplicates: name=\(name ?? "nil"), company=\(company ?? "nil")")

        // 検索条件がない場合は空を返す
        guard name != nil || company != nil || email != nil else {
            return []
        }

        // 全Personを取得
        let descriptor = FetchDescriptor<Person>()
        guard let persons = try? modelContext.fetch(descriptor) else {
            logger.error("Failed to fetch persons")
            return []
        }

        var candidates: [DuplicateCandidate] = []

        for person in persons {
            let score = calculateMatchScore(
                person: person,
                name: name,
                company: company,
                email: email
            )

            if score > 0 {
                candidates.append(DuplicateCandidate(person: person, matchScore: score))
            }
        }

        // スコア順にソート
        candidates.sort { $0.matchScore > $1.matchScore }

        logger.info("Found \(candidates.count) duplicate candidates")
        return candidates
    }

    /// 最も可能性の高い重複候補を取得
    /// - Parameters:
    ///   - name: 氏名
    ///   - company: 会社名
    ///   - email: メールアドレス
    /// - Returns: 最も可能性の高い候補（閾値を超える場合のみ）
    func findBestMatch(
        name: String?,
        company: String?,
        email: String?
    ) -> DuplicateCandidate? {
        let candidates = findDuplicates(name: name, company: company, email: email)

        // 閾値: 0.7以上で重複とみなす
        guard let best = candidates.first, best.matchScore >= 0.7 else {
            return nil
        }

        return best
    }

    /// 完全一致する人を検索
    /// - Parameters:
    ///   - name: 氏名
    ///   - company: 会社名
    /// - Returns: 完全一致するPerson
    func findExactMatch(name: String, company: String?) -> Person? {
        let descriptor = FetchDescriptor<Person>(
            predicate: #Predicate<Person> { person in
                person.name == name
            }
        )

        guard let persons = try? modelContext.fetch(descriptor) else {
            return nil
        }

        // 会社名も一致するものを優先
        if let company = company {
            if let match = persons.first(where: { $0.primaryCompany == company }) {
                return match
            }
        }

        return persons.first
    }

    // MARK: - Private Methods

    /// マッチスコアを計算（0.0〜1.0）
    private func calculateMatchScore(
        person: Person,
        name: String?,
        company: String?,
        email: String?
    ) -> Double {
        var score: Double = 0
        var weights: Double = 0

        // 名前の一致度（重み: 0.5）
        if let name = name, !name.isEmpty {
            let nameScore = calculateStringMatchScore(person.name, name)
            score += nameScore * 0.5
            weights += 0.5
        }

        // 会社名の一致度（重み: 0.3）
        if let company = company, !company.isEmpty,
           let personCompany = person.primaryCompany {
            let companyScore = calculateStringMatchScore(personCompany, company)
            score += companyScore * 0.3
            weights += 0.3
        }

        // メールアドレスの一致（重み: 0.2、完全一致のみ）
        if let email = email, !email.isEmpty {
            let emailMatched = person.businessCards.contains { card in
                card.emails.contains { $0.lowercased() == email.lowercased() }
            }
            if emailMatched {
                score += 0.2
            }
            weights += 0.2
        }

        // 重み付けを正規化
        return weights > 0 ? score / weights : 0
    }

    /// 文字列の一致度を計算
    private func calculateStringMatchScore(_ str1: String, _ str2: String) -> Double {
        // 完全一致
        if str1 == str2 {
            return 1.0
        }

        // 正規化して比較
        let normalized1 = normalizeString(str1)
        let normalized2 = normalizeString(str2)

        if normalized1 == normalized2 {
            return 0.95
        }

        // 部分一致
        if normalized1.contains(normalized2) || normalized2.contains(normalized1) {
            return 0.8
        }

        // レーベンシュタイン距離による類似度
        let distance = levenshteinDistance(normalized1, normalized2)
        let maxLength = max(normalized1.count, normalized2.count)
        if maxLength == 0 {
            return 0
        }

        let similarity = 1.0 - Double(distance) / Double(maxLength)
        return max(0, similarity)
    }

    /// 文字列を正規化（空白削除、小文字化、全角→半角など）
    private func normalizeString(_ str: String) -> String {
        var result = str
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        // 全角スペースを半角に
        result = result.replacingOccurrences(of: "　", with: " ")

        // 全角英数字を半角に
        result = result.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? result

        // スペースを削除
        result = result.replacingOccurrences(of: " ", with: "")

        return result
    }

    /// レーベンシュタイン距離を計算
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let s1 = Array(str1)
        let s2 = Array(str2)
        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m {
            matrix[i][0] = i
        }
        for j in 0...n {
            matrix[0][j] = j
        }

        for i in 1...m {
            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // 削除
                    matrix[i][j - 1] + 1,      // 挿入
                    matrix[i - 1][j - 1] + cost // 置換
                )
            }
        }

        return matrix[m][n]
    }
}

// MARK: - DuplicateCandidate

/// 重複候補。
struct DuplicateCandidate {
    /// 候補のPerson
    let person: Person

    /// マッチスコア（0.0〜1.0）
    let matchScore: Double

    /// マッチの確信度レベル
    var confidenceLevel: ConfidenceLevel {
        switch matchScore {
        case 0.9...:
            return .high
        case 0.7..<0.9:
            return .medium
        default:
            return .low
        }
    }

    enum ConfidenceLevel {
        case high    // ほぼ確実に同一人物
        case medium  // 可能性が高い
        case low     // 可能性あり
    }
}
