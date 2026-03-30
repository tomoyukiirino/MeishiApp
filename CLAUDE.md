# MeishiApp - 名刺管理アプリ

## プロジェクト概要

MeishiAppは、日本の医療従事者向けに設計されたiOS名刺管理アプリケーションです。名刺の撮影、OCR、AI構造化、連絡先管理を提供します。

## 技術スタック

- **言語**: Swift 5.9+
- **UI**: SwiftUI
- **データ永続化**: SwiftData
- **最小iOS**: iOS 17.0
- **アーキテクチャ**: MVVM + サービス層

## プロジェクト構造

```
MeishiApp/
├── Models/           # SwiftData モデル
│   ├── Person.swift          # 人物（中心エンティティ）
│   ├── BusinessCard.swift    # 名刺
│   ├── Encounter.swift       # 出会いの記録
│   └── Tag.swift             # タグ
├── Views/            # SwiftUI ビュー
│   ├── PersonList/           # 人物一覧
│   ├── PersonDetail/         # 人物詳細・編集
│   ├── CardRegistration/     # 名刺登録フロー
│   ├── Capture/              # 撮影画面
│   └── Settings/             # 設定画面
├── Services/         # ビジネスロジック
│   ├── LLM/                  # LLMサービス（マルチプロバイダー対応）
│   │   ├── LLMServiceProtocol.swift    # 共通プロトコル
│   │   ├── LLMServiceFactory.swift     # ファクトリー
│   │   ├── LLMSettingsManager.swift    # 設定管理
│   │   ├── KeychainService.swift       # APIキー保存
│   │   └── Adapters/                   # 各LLMアダプター
│   │       ├── ClaudeAdapter.swift
│   │       ├── ChatGPTAdapter.swift
│   │       ├── GeminiAdapter.swift
│   │       └── PerplexityAdapter.swift
│   ├── OCRService.swift              # Vision OCR
│   ├── AuthenticationService.swift   # 生体認証
│   ├── BackupService.swift           # iCloudバックアップ
│   └── ImageStorageService.swift     # 画像保存
└── Resources/        # リソース
    └── Localizable.strings   # 日本語ローカライズ
```

## 主要な機能

### 名刺管理
- 名刺の撮影（表面・裏面）
- Vision Framework によるOCR
- AI構造化（複数LLMプロバイダー対応）
- 重複検出と統合機能

### LLMサービス
マルチLLMプロバイダーをサポート:
- Claude (Anthropic)
- ChatGPT (OpenAI)
- Gemini (Google)
- Perplexity

```swift
// LLMサービスの使用例
if let service = LLMServiceFactory.shared.createService() {
    let data = try await service.structure(
        image: cardImage,
        ocrText: ocrText,
        mode: LLMSettingsManager.shared.privacyMode
    )
}
```

### プライバシーモード
- **プライバシー優先**: OCRテキストのみ送信
- **精度優先**: 名刺画像も送信（より正確な構造化）

## ビルドとテスト

```bash
# ビルド
xcodebuild -project MeishiApp.xcodeproj -scheme MeishiApp -sdk iphonesimulator build

# テスト
xcodebuild -project MeishiApp.xcodeproj -scheme MeishiApp -sdk iphonesimulator test
```

## コーディング規約

### Swift スタイル
- 日本語コメントを使用
- MARK コメントでセクション分け
- Optional unwrapping は `guard` を優先
- async/await を使用（Combine は避ける）

### SwiftData
- `@Model` マクロを使用
- `@Relationship` でリレーション定義
- cascade 削除ルールを適切に設定

### SwiftUI
- `@Observable` マクロ（iOS 17+）
- `@State`, `@Binding` の適切な使用
- `String(localized:)` でローカライズ

## APIキー管理

APIキーはKeychainに安全に保存:

```swift
// 保存
KeychainService.shared.saveAPIKey(apiKey, for: .claude)

// 取得
let key = KeychainService.shared.getAPIKey(for: .claude)

// 削除
KeychainService.shared.deleteAPIKey(for: .claude)
```

## ローカライズ

すべての文字列は `Localizable.strings` で管理:

```swift
// 使用例
Text(String(localized: "settings.aiStructuring"))
```

## 重要な注意事項

1. **旧ClaudeAPIService**: `Services/ClaudeAPIService.swift` は互換性のために残していますが、新しいコードでは `LLMServiceFactory` を使用してください。

2. **画像サポート**: Perplexity は画像入力をサポートしていないため、プライバシー優先モードのみ使用可能です。

3. **設定の移行**: `LLMSettingsManager.migrateFromLegacySettings()` で旧設定から自動移行されます。

## 依存関係

外部依存なし（すべて Apple 標準フレームワークを使用）
