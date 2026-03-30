import Foundation
import SwiftData
import ZIPFoundation
import os.log

// MARK: - BackupService

/// バックアップ・リストアサービス。
/// SQLite + JPEG画像をZIP形式でアーカイブする。
actor BackupService {
    // MARK: - Singleton

    static let shared = BackupService()

    // MARK: - Properties

    private let logger = Logger(subsystem: "jp.akkurat.MeishiApp", category: "BackupService")
    private let fileManager = FileManager.default

    /// iCloud Driveへの自動バックアップが有効か
    var isAutoBackupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "isAutoBackupEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "isAutoBackupEnabled") }
    }

    /// 最後のバックアップ日時
    var lastBackupDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastBackupDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastBackupDate") }
    }

    // MARK: - Directories

    /// Documentsディレクトリ
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 画像ディレクトリ
    private var imagesDirectory: URL {
        documentsDirectory.appendingPathComponent("images", isDirectory: true)
    }

    /// SwiftDataのストアファイル
    private var swiftDataStoreURL: URL {
        documentsDirectory.appendingPathComponent("default.store")
    }

    /// iCloud DriveのURL
    private var iCloudURL: URL? {
        fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Settings

    /// 自動バックアップを有効/無効にする
    func setAutoBackupEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "isAutoBackupEnabled")
    }

    // MARK: - Backup Creation

    /// バックアップを作成（ModelContextを使用）
    /// - Parameter modelContext: SwiftDataのModelContext
    /// - Returns: バックアップファイルのURL
    func createBackup(modelContext: ModelContext) async throws -> URL {
        // ModelContextの変更を保存
        try modelContext.save()
        return try await createBackup()
    }

    /// バックアップを作成
    /// - Returns: バックアップファイルのURL
    func createBackup() async throws -> URL {
        logger.info("Starting backup creation")

        // バックアップファイル名
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        let backupFileName = "meishi_backup_\(dateString).zip"

        // 一時ディレクトリにバックアップフォルダを作成
        let tempBackupDir = fileManager.temporaryDirectory.appendingPathComponent("backup_\(dateString)", isDirectory: true)
        try fileManager.createDirectory(at: tempBackupDir, withIntermediateDirectories: true)

        defer {
            // クリーンアップ
            try? fileManager.removeItem(at: tempBackupDir)
        }

        // SwiftDataのストアをコピー
        let storeFiles = try findSwiftDataStoreFiles()
        for storeFile in storeFiles {
            let destURL = tempBackupDir.appendingPathComponent(storeFile.lastPathComponent)
            try fileManager.copyItem(at: storeFile, to: destURL)
        }

        // 画像フォルダをコピー
        if fileManager.fileExists(atPath: imagesDirectory.path) {
            let destImagesDir = tempBackupDir.appendingPathComponent("images", isDirectory: true)
            try fileManager.copyItem(at: imagesDirectory, to: destImagesDir)
        }

        // ZIPファイルを作成
        let zipURL = fileManager.temporaryDirectory.appendingPathComponent(backupFileName)
        try fileManager.zipItem(at: tempBackupDir, to: zipURL)

        // 最終バックアップ日時を更新
        lastBackupDate = Date()

        logger.info("Backup created: \(backupFileName)")
        return zipURL
    }

    /// SwiftDataのストアファイルを検索
    private func findSwiftDataStoreFiles() throws -> [URL] {
        var storeFiles: [URL] = []

        let contents = try fileManager.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: nil
        )

        for url in contents {
            let fileName = url.lastPathComponent
            // SwiftDataのストアファイル（.store, .store-shm, .store-wal）
            if fileName.hasPrefix("default.store") || fileName.hasSuffix(".store") ||
               fileName.hasSuffix(".store-shm") || fileName.hasSuffix(".store-wal") {
                storeFiles.append(url)
            }
        }

        return storeFiles
    }

    // MARK: - Backup to iCloud

    /// iCloud Driveにバックアップを保存
    func backupToiCloud() async throws {
        guard let iCloudURL = iCloudURL else {
            throw BackupError.iCloudNotAvailable
        }

        // iCloudディレクトリを作成
        if !fileManager.fileExists(atPath: iCloudURL.path) {
            try fileManager.createDirectory(at: iCloudURL, withIntermediateDirectories: true)
        }

        // バックアップを作成
        let backupURL = try await createBackup()

        // iCloudにコピー
        let destURL = iCloudURL.appendingPathComponent(backupURL.lastPathComponent)

        // 既存ファイルがあれば削除
        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }

        try fileManager.copyItem(at: backupURL, to: destURL)

        // 一時ファイルを削除
        try fileManager.removeItem(at: backupURL)

        // 古いバックアップを削除（最新5件を保持）
        try await cleanupOldBackups(in: iCloudURL, keepCount: 5)

        logger.info("Backup saved to iCloud")
    }

    /// 古いバックアップを削除
    private func cleanupOldBackups(in directory: URL, keepCount: Int) async throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        )

        let backupFiles = contents
            .filter { $0.pathExtension == "zip" && $0.lastPathComponent.hasPrefix("meishi_backup_") }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }

        // keepCount以降のファイルを削除
        if backupFiles.count > keepCount {
            for file in backupFiles.dropFirst(keepCount) {
                try fileManager.removeItem(at: file)
                logger.info("Deleted old backup: \(file.lastPathComponent)")
            }
        }
    }

    // MARK: - Restore

    /// バックアップから復元（ModelContextを使用）
    /// - Parameters:
    ///   - backupURL: バックアップZIPファイルのURL
    ///   - modelContext: SwiftDataのModelContext
    func restoreBackup(from backupURL: URL, modelContext: ModelContext) async throws {
        try await restoreFromBackup(at: backupURL)
        // Note: アプリの再起動が必要な場合がある
    }

    /// バックアップから復元
    /// - Parameter backupURL: バックアップZIPファイルのURL
    func restoreFromBackup(at backupURL: URL) async throws {
        logger.info("Starting restore from backup")

        // 一時ディレクトリに解凍
        let tempRestoreDir = fileManager.temporaryDirectory.appendingPathComponent("restore_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempRestoreDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempRestoreDir)
        }

        // ZIPを解凍
        try fileManager.unzipItem(at: backupURL, to: tempRestoreDir)

        // 解凍されたファイルを確認
        let contents = try fileManager.contentsOfDirectory(at: tempRestoreDir, includingPropertiesForKeys: nil)

        // バックアップフォルダ内のファイルを取得（ZIPの構造によって異なる場合がある）
        var sourceDir = tempRestoreDir
        if contents.count == 1, contents[0].hasDirectoryPath {
            sourceDir = contents[0]
        }

        // 既存のデータをバックアップ（安全のため）
        let existingBackupDir = fileManager.temporaryDirectory.appendingPathComponent("existing_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: existingBackupDir, withIntermediateDirectories: true)

        // 既存のストアファイルを移動
        let existingStoreFiles = try findSwiftDataStoreFiles()
        for file in existingStoreFiles {
            let destURL = existingBackupDir.appendingPathComponent(file.lastPathComponent)
            try fileManager.moveItem(at: file, to: destURL)
        }

        // 既存の画像フォルダを移動
        if fileManager.fileExists(atPath: imagesDirectory.path) {
            let destImagesDir = existingBackupDir.appendingPathComponent("images", isDirectory: true)
            try fileManager.moveItem(at: imagesDirectory, to: destImagesDir)
        }

        do {
            // 復元ファイルをコピー
            let restoreContents = try fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)

            for item in restoreContents {
                let fileName = item.lastPathComponent

                if fileName == "images" {
                    // 画像フォルダ
                    try fileManager.copyItem(at: item, to: imagesDirectory)
                } else if fileName.hasSuffix(".store") || fileName.hasSuffix(".store-shm") || fileName.hasSuffix(".store-wal") {
                    // SwiftDataストアファイル
                    let destURL = documentsDirectory.appendingPathComponent(fileName)
                    try fileManager.copyItem(at: item, to: destURL)
                }
            }

            // 成功したら既存バックアップを削除
            try fileManager.removeItem(at: existingBackupDir)

            logger.info("Restore completed successfully")
        } catch {
            // 失敗時は既存データを復元
            logger.error("Restore failed, reverting: \(error.localizedDescription)")

            // 復元に失敗したファイルを削除
            for file in try findSwiftDataStoreFiles() {
                try? fileManager.removeItem(at: file)
            }
            if fileManager.fileExists(atPath: imagesDirectory.path) {
                try? fileManager.removeItem(at: imagesDirectory)
            }

            // 既存データを戻す
            let existingContents = try fileManager.contentsOfDirectory(at: existingBackupDir, includingPropertiesForKeys: nil)
            for item in existingContents {
                let fileName = item.lastPathComponent
                if fileName == "images" {
                    try fileManager.moveItem(at: item, to: imagesDirectory)
                } else {
                    let destURL = documentsDirectory.appendingPathComponent(fileName)
                    try fileManager.moveItem(at: item, to: destURL)
                }
            }

            throw BackupError.restoreFailed(error)
        }
    }

    // MARK: - iCloud Backups List

    /// iCloud Driveのバックアップ一覧を取得
    func listICloudBackups() async throws -> [BackupFile] {
        guard let iCloudURL = iCloudURL else {
            throw BackupError.iCloudNotAvailable
        }

        guard fileManager.fileExists(atPath: iCloudURL.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: iCloudURL,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        )

        let backupFiles = contents
            .filter { $0.pathExtension == "zip" && $0.lastPathComponent.hasPrefix("meishi_backup_") }
            .compactMap { url -> BackupFile? in
                guard let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
                      let creationDate = resourceValues.creationDate,
                      let fileSize = resourceValues.fileSize else {
                    return nil
                }
                return BackupFile(url: url, createdAt: creationDate, fileSize: Int64(fileSize))
            }
            .sorted { $0.createdAt > $1.createdAt }

        return backupFiles
    }

    // MARK: - Utility

    /// iCloud Driveが利用可能か
    var isICloudAvailable: Bool {
        iCloudURL != nil
    }

    /// 利用可能なバックアップファイル一覧を取得（iCloud + ローカル）
    func listAvailableBackups() async -> [URL] {
        var backups: [URL] = []

        // iCloudのバックアップ
        if let iCloudBackups = try? await listICloudBackups() {
            backups.append(contentsOf: iCloudBackups.map { $0.url })
        }

        // ローカルの一時バックアップ
        let tempDir = fileManager.temporaryDirectory
        if let contents = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey]) {
            let localBackups = contents
                .filter { $0.pathExtension == "zip" && $0.lastPathComponent.hasPrefix("meishi_backup_") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return date1 > date2
                }
            backups.append(contentsOf: localBackups)
        }

        return backups
    }
}

// MARK: - BackupFile

/// バックアップファイル情報。
struct BackupFile: Identifiable {
    let id = UUID()
    let url: URL
    let createdAt: Date
    let fileSize: Int64

    var fileName: String {
        url.lastPathComponent
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - BackupError

enum BackupError: LocalizedError {
    case iCloudNotAvailable
    case backupCreationFailed(Error)
    case restoreFailed(Error)
    case invalidBackupFile

    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud Driveが利用できません"
        case .backupCreationFailed:
            return String(localized: "backup.failed")
        case .restoreFailed:
            return String(localized: "backup.restoreFailed")
        case .invalidBackupFile:
            return "無効なバックアップファイルです"
        }
    }
}

// MARK: - BackupView

import SwiftUI

/// バックアップ・リストア画面。
struct BackupView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss

    @State private var isAutoBackupEnabled = false
    @State private var isCreatingBackup = false
    @State private var isRestoring = false
    @State private var backupFiles: [BackupFile] = []
    @State private var showingFilePicker = false
    @State private var showingShareSheet = false
    @State private var exportedBackupURL: URL?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showingRestoreConfirmation = false
    @State private var selectedBackupForRestore: BackupFile?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // 自動バックアップ
                Section(header: Text(String(localized: "settings.backup.auto"))) {
                    Toggle(isOn: $isAutoBackupEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "backup.icloud.enabled"))
                            Text(String(localized: "backup.icloud"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: isAutoBackupEnabled) { _, newValue in
                        Task {
                            await BackupService.shared.setAutoBackupEnabled(newValue)
                        }
                    }
                }

                // 手動バックアップ
                Section(header: Text(String(localized: "settings.backup.manual"))) {
                    Button {
                        Task {
                            await createBackup()
                        }
                    } label: {
                        HStack {
                            Text("バックアップを作成")
                            Spacer()
                            if isCreatingBackup {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isCreatingBackup)

                    if let lastDate = UserDefaults.standard.object(forKey: "lastBackupDate") as? Date {
                        Text("最終バックアップ: \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // iCloudバックアップ一覧
                if !backupFiles.isEmpty {
                    Section(header: Text("iCloud Driveのバックアップ")) {
                        ForEach(backupFiles) { backup in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(backup.formattedDate)
                                        .font(.subheadline)
                                    Text(backup.formattedSize)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("復元") {
                                    selectedBackupForRestore = backup
                                    showingRestoreConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .disabled(isRestoring)
                            }
                        }
                    }
                }

                // 手動リストア
                Section(header: Text(String(localized: "settings.backup.restore"))) {
                    Button {
                        showingFilePicker = true
                    } label: {
                        HStack {
                            Text(String(localized: "backup.selectFile"))
                            Spacer()
                            if isRestoring {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRestoring)
                }

                // メッセージ
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if let successMessage = successMessage {
                    Section {
                        Text(successMessage)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle(String(localized: "settings.backup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                BackupFilePicker { url in
                    Task {
                        await restoreFromFile(url)
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedBackupURL {
                    ShareSheet(items: [url])
                }
            }
            .confirmationDialog(
                String(localized: "backup.confirm.title"),
                isPresented: $showingRestoreConfirmation,
                titleVisibility: .visible
            ) {
                Button("復元", role: .destructive) {
                    if let backup = selectedBackupForRestore {
                        Task {
                            await restoreFromFile(backup.url)
                        }
                    }
                }
            } message: {
                Text(String(localized: "backup.confirm.message"))
            }
            .task {
                await loadBackupList()
                isAutoBackupEnabled = await BackupService.shared.isAutoBackupEnabled
            }
        }
    }

    // MARK: - Methods

    private func createBackup() async {
        isCreatingBackup = true
        errorMessage = nil
        successMessage = nil

        do {
            let url = try await BackupService.shared.createBackup()
            exportedBackupURL = url
            showingShareSheet = true
            successMessage = String(localized: "backup.created")
        } catch {
            errorMessage = error.localizedDescription
        }

        isCreatingBackup = false
    }

    private func loadBackupList() async {
        do {
            backupFiles = try await BackupService.shared.listICloudBackups()
        } catch {
            backupFiles = []
        }
    }

    private func restoreFromFile(_ url: URL) async {
        isRestoring = true
        errorMessage = nil
        successMessage = nil

        do {
            try await BackupService.shared.restoreFromBackup(at: url)
            successMessage = String(localized: "backup.restored")
        } catch {
            errorMessage = error.localizedDescription
        }

        isRestoring = false
    }
}

// MARK: - BackupFilePicker

/// バックアップファイル選択ピッカー。
struct BackupFilePicker: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void

        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onSelect(url)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BackupView()
}
