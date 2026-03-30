# Claude Code 実装プロンプト v2.0 — 名刺管理アプリ

## このドキュメントについて

このプロンプトは、Claude Code（CLI / VS Code拡張）でiOS名刺管理アプリを開発する際の指示書です。`./bc/docs/meishi-app-spec-v2.md` にプロダクト仕様書があります。必ず最初に読んでから実装を開始してください。

---

## プロジェクト概要

「人の記憶のためのアプリ」。データは原則端末内に完結し、第三者のサーバーにはアップロードしない。有料オプションでClaude APIによるAI構造化機能を提供する。データモデルは **Person（人）中心** で設計する。

- プラットフォーム: iOS 17+ / SwiftUI
- 言語: Swift
- プロジェクトルート: `./bc/`
- 仕様書: `./bc/docs/meishi-app-spec-v2.md`

---

## ディレクトリ構成

```
bc/
├── docs/
│   ├── meishi-app-spec-v2.md    # プロダクト仕様書（必読）
│   └── claude-code-prompt.md    # このファイル
├── MeishiApp/
│   ├── App/
│   │   └── MeishiApp.swift       # アプリエントリポイント
│   ├── Models/
│   │   ├── Person.swift           # 人 — 中心エンティティ
│   │   ├── BusinessCard.swift     # 名刺 — Personに属する証跡
│   │   ├── Encounter.swift        # 出会いの記録
│   │   ├── Tag.swift              # タグ
│   │   └── FeatureFlags.swift     # フィーチャーフラグ（課金制御）
│   ├── Views/
│   │   ├── PersonList/            # 人の一覧（リスト/グリッド/サムネイル）
│   │   ├── PersonDetail/          # 人の詳細画面（名刺履歴・出会い履歴）
│   │   ├── CardCapture/           # 名刺撮影・取り込み
│   │   ├── CardRegistration/      # 登録フロー（OCR→構造化→重複検出→出会い記録→保存）
│   │   ├── FacePhoto/             # 顔写真の紐づけ（Phase 2）
│   │   ├── FaceSearch/            # 顔検索・逆引き（Phase 3）
│   │   ├── Settings/              # 設定画面
│   │   └── Components/            # 共通UIコンポーネント
│   ├── Services/
│   │   ├── OCRService.swift            # Apple Vision OCR
│   │   ├── FaceDetectionService.swift  # 顔検出（Vision Framework）
│   │   ├── FaceEmbeddingService.swift  # 顔特徴量抽出（CoreML）— Phase 3
│   │   ├── ImageStorageService.swift   # 画像のファイルシステム保存・読み込み
│   │   ├── ClaudeAPIService.swift      # Claude API連携（有料版）— Phase 2
│   │   ├── ContactService.swift        # iPhone連絡先への片方向エクスポート
│   │   ├── BackupService.swift         # バックアップ・リストア
│   │   ├── ExportService.swift         # CSV/vCardエクスポート
│   │   └── AuthenticationService.swift # 生体認証ロック
│   ├── MLModels/                  # Phase 3で追加
│   │   └── MobileFaceNet.mlmodel  # 顔認識CoreMLモデル
│   ├── Utilities/
│   │   ├── ImageProcessor.swift   # 画像クロップ・補正
│   │   └── DuplicateDetector.swift # 重複検出
│   ├── Resources/
│   │   └── Localizable.strings    # i18n文字列（日本語）
│   └── Extensions/
├── MeishiAppTests/
└── MeishiApp.xcodeproj
```

---

## 開発ルール（全フェーズ共通）

### 1. コーディング規約

- **Swift 5.9+** / **SwiftUI** を使用
- **SwiftData** をデータ永続化に使用（Core Dataではない）
- MVVM アーキテクチャ: View → ViewModel → Service/Model
- 1ファイル1責務。ファイルが300行を超えたら分割を検討
- プロパティ名・メソッド名は英語。コメントは日本語可
- `// MARK: -` でセクション区切りを入れる
- ForceUnwrap（`!`）は使わない。`guard let` または `if let` を使う
- エラーハンドリングは `do-catch` で適切に処理。ユーザーに見せるエラーメッセージは日本語
- `print()` デバッグは残さない。必要なログは `os.Logger` を使う

### 2. i18n（国際化）— 最重要ルール

**UIに表示するすべての文字列は `Localizable.strings` に外出しすること。**

```swift
// ❌ 絶対にやらない
Text("名刺を追加")
Button("保存")

// ✅ 必ずこうする
Text(String(localized: "card.add"))
Button(String(localized: "common.save"))
```

キーの命名規則:
- `common.*` — 共通（保存、キャンセル、削除など）
- `person.*` — 人関連
- `card.*` — 名刺関連
- `encounter.*` — 出会いの記録
- `capture.*` — 撮影・取り込み
- `ocr.*` — OCR・構造化
- `face.*` — 顔写真関連
- `settings.*` — 設定
- `backup.*` — バックアップ
- `export.*` — エクスポート
- `error.*` — エラーメッセージ
- `auth.*` — 生体認証

日付・数値のフォーマットは `Locale.current` に依存させる。固定フォーマットにしない。
レイアウトは固定幅にしない。長い言語（ドイツ語等）でも崩れない設計にする。

### 3. プライバシー・セキュリティ

- ネットワーク通信は `ClaudeAPIService` 以外で行わない
- `ClaudeAPIService` は有料版機能のみ。無料版ではインスタンス化すらしない
- APIキーはソースコードに埋め込まない（後述「APIキーの管理」参照）
- カメラ・写真ライブラリ・連絡先へのアクセスは、使用時に初めてリクエスト
- Info.plist に `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSContactsUsageDescription`, `NSFaceIDUsageDescription` を適切な日本語で記載
- **すべてのデータファイルに `NSFileProtectionComplete` を設定**（端末ロック中はアクセス不可）
- 画像保存時に `ImageStorageService` で FileProtection 属性を付与

### 4. テスト

- Service層のユニットテストを書く（特にOCR、重複検出、エクスポート）
- ViewModelのロジックテストを書く
- UIテストはPhase 4で追加

---

## チーム開発時の注意事項

### APIキーの管理

Claude APIキーは絶対にソースコードやリポジトリに含めないこと。

```swift
// ❌ 絶対にやらない
let apiKey = "sk-ant-api03-xxxxx"

// ✅ 環境変数または設定ファイルから読み込む
```

**開発環境での運用:**
1. `.env` ファイルをプロジェクトルートに作成（APIキーを記載）
2. `.gitignore` に `.env` を追加
3. Xcodeの Scheme設定で環境変数として読み込み
4. `ClaudeAPIService` は `ProcessInfo.processInfo.environment["CLAUDE_API_KEY"]` で取得

**本番環境（App Store配布後）の設計:**
サブスクリプション課金ユーザーのAPIコールは、Akkuratが運用するプロキシサーバー経由で行う。APIキーはサーバー側で管理し、アプリにはAPIキーを含めない。

### Git運用

```
main        — リリース可能な安定版
develop     — 開発統合ブランチ
feature/*   — 機能開発（feature/person-model, feature/ocr-service 等）
bugfix/*    — バグ修正
```

- `main` への直接pushは禁止
- feature ブランチは `develop` から切り、PRで `develop` にマージ
- コミットメッセージは日本語可。`feat:`, `fix:`, `refactor:`, `docs:` プレフィックスを付ける

### .gitignore に必ず含めるもの

```
.env
*.xcuserdata
*.xcworkspace
DerivedData/
.DS_Store
Pods/
```

### 並行開発時の競合回避

- **Models/**: データモデルの変更は必ずチーム内で共有してから行う。SwiftDataのスキーママイグレーションに影響する
- **Localizable.strings**: 競合しやすい。キーの追加はファイル末尾に追記し、定期的にソートする
- **Info.plist**: 複数人が同時に編集しない
- **Services/**: 各Serviceは独立性を保つ。Service間の依存はProtocolを介して疎結合にする

---

## フェーズ別実装指示

### Phase 1: コアMVP

仕様書のセクション9「Phase 1」に対応。最小限の動作するアプリを作る。

**実装順序:**

1. **プロジェクトセットアップ**
   - Xcodeプロジェクト作成（MeishiApp, iOS 17+, SwiftUI, SwiftData）
   - ディレクトリ構成を上記の通り作成
   - Info.plistにカメラ・写真ライブラリ・Face IDの権限記載
   - Localizable.strings の雛形作成
   - FileProtection設定

2. **データモデル（SwiftData）— Person中心設計（最重要）**

   仕様書セクション6に従って定義。`@Model` マクロを使用。

   ```swift
   // Person — 中心エンティティ
   @Model
   class Person {
       var id: UUID
       var name: String
       var nameReading: String?
       var primaryCompany: String?   // 最新の名刺から自動更新
       var primaryTitle: String?     // 最新の名刺から自動更新
       var memo: String?
       var facePhotoPath: String?    // Phase 2で使用
       // var faceEmbedding: [Float]? // Phase 3で追加
       @Relationship(deleteRule: .cascade) var businessCards: [BusinessCard]
       @Relationship(deleteRule: .cascade) var encounters: [Encounter]
       @Relationship var tags: [Tag]
       var createdAt: Date
       var updatedAt: Date
   }
   
   // BusinessCard — Personに属する証跡
   @Model
   class BusinessCard {
       var id: UUID
       var person: Person?
       var frontImagePath: String
       var backImagePath: String?
       var company: String?
       var department: String?
       var title: String?
       var phoneNumbers: [String]
       var emails: [String]
       var address: String?
       var website: String?
       var ocrTextFront: String?
       var ocrTextBack: String?
       var acquiredAt: Date
       var createdAt: Date
   }
   
   // Encounter — 出会いの記録
   @Model
   class Encounter {
       var id: UUID
       var person: Person?
       var eventName: String?
       var date: Date?
       var location: String?
       var memo: String?
       var businessCard: BusinessCard?  // この出会いで受け取った名刺
       var createdAt: Date
   }
   
   // Tag
   @Model
   class Tag {
       var id: UUID
       var name: String
       @Relationship var persons: [Person]
   }
   ```

   **画像はファイルシステムに保存、DBにはパスのみ格納:**
   - SwiftDataに画像Data型を直接格納しない
   - `images/cards/{uuid}_front.jpg`, `images/faces/{uuid}_face.jpg`
   - ImageStorageServiceで読み書きを管理
   - FileProtection属性を保存時に付与

3. **生体認証ロック（AuthenticationService）**
   - LocalAuthentication フレームワークで Face ID / Touch ID
   - アプリ起動時 + バックグラウンドからの復帰時に認証要求
   - 設定画面でON/OFF可能
   - 認証失敗時はアプリの内容を表示しない

4. **名刺撮影・取り込み（CardCapture）**
   - AVFoundationでカメラ起動
   - VNDetectRectanglesRequestで名刺の矩形検出
   - 自動クロップ・傾き補正（CIFilter / CIPerspectiveCorrection）
   - 表面撮影 → 「裏面も撮影しますか？」プロンプト → 裏面撮影
   - カメラロールからの選択も可能（PHPickerViewController）

5. **オンデバイスOCR（OCRService）**
   - VNRecognizeTextRequestで表面・裏面それぞれにOCR実行
   - recognitionLanguages: デフォルトは `["ja", "en", "zh-Hans", "zh-Hant", "ko"]`
   - 設定画面から言語追加・優先順位変更可能にする
   - automaticallyDetectsLanguage: true
   - recognitionLevel: .accurate

6. **手動構造化（CardRegistration）— 3層設計**
   - **自動推定**: 電話番号形式、メール形式、URL形式を正規表現で検出し対応フィールドに自動入力
   - **ユーザー確認**: 推定結果をまず表示。ユーザーは誤りだけ修正する
   - **不完全でも保存可能**: 必須は「氏名 or 会社名」と「名刺画像」のみ。住所・Web等は未設定OK
   - 1件あたりの入力時間を最小化し、「とりあえず保存して後から整理」を許容する

7. **重複検出（DuplicateDetector）— 構造化の直後に実行**
   - OCR/構造化で氏名・会社名が確定した時点でSwiftDataのPersonを検索
   - 氏名 + 会社名 + メールアドレスで既存Personと照合
   - 一致候補があれば即座にアラート:
     「〇〇さんは既に登録されています。この名刺を〇〇さんに追加しますか？それとも別の方として新規登録しますか？」
   - 既存Personに追加 → 新しいBusinessCardとEncounterがそのPersonに紐づく
   - **メモ入力前に検出すること（最重要UXルール）**

8. **出会いの記録 + メモ**
   - 重複検出の後（新規 or 既存Person確定後）に入力
   - Encounterモデルとして保存（eventName, date, location, memo）
   - イベント名は新規入力 or 過去のEncounterから選択（オートコンプリート）
   - メモはスキャンフロー内で完結（別画面に遷移しない）

9. **一覧・検索（PersonList）**
   - リスト表示（デフォルト）: 名前、会社名（primaryCompany）、役職（primaryTitle）
   - 顔写真サムネイル or イニシャルアイコン
   - インクリメンタルサーチ（氏名、会社名、役職、メモ、イベント名、タグで横断検索）
   - ソート: 最近登録順（デフォルト）、名前順、会社名順
   - SwiftDataの `@Query` と `#Predicate` を使用

10. **Person詳細・編集・削除（PersonDetail）**
    - 顔写真（Phase 2で追加）
    - 氏名・ふりがな・現在の会社名・役職
    - メモ
    - **名刺履歴**: この人のBusinessCardを時系列で表示（名刺画像の表/裏切り替え）
    - **出会いの記録一覧**: Encounterを時系列で表示
    - タグ
    - 編集モード
    - 削除（確認ダイアログ付き。Personを削除すると配下のBusinessCard, Encounterも cascade 削除）

### Phase 2: AI構造化・顔写真・補助機能

1. **Claude API自動構造化（ClaudeAPIService）**
   - Anthropic Messages API (`https://api.anthropic.com/v1/messages`) を使用
   - モデル: `claude-sonnet-4-20250514`
   - **プライバシー優先モード**: OCRテキストをuser messageとして送信
   - **精度優先モード**: 名刺画像をbase64エンコードしてimage contentとして送信
   - 設定画面でモード切り替えトグル
   - AI構造化の初回利用時に送信内容と削除ポリシーを説明するダイアログを表示

   ```swift
   // プライバシー優先モード
   {
     "model": "claude-sonnet-4-20250514",
     "max_tokens": 1024,
     "messages": [{
       "role": "user",
       "content": "以下は名刺のOCRテキストです。JSON形式で構造化してください。\nフィールド: name, nameReading, company, department, title, phoneNumbers(配列), emails(配列), address, website\n\nOCRテキスト:\n\(ocrText)"
     }]
   }
   
   // 精度優先モード
   {
     "model": "claude-sonnet-4-20250514",
     "max_tokens": 1024,
     "messages": [{
       "role": "user",
       "content": [
         {
           "type": "image",
           "source": {
             "type": "base64",
             "media_type": "image/jpeg",
             "data": "(base64エンコードされた名刺画像)"
           }
         },
         {
           "type": "text",
           "text": "この名刺画像から情報を読み取り、JSON形式で構造化してください。\nフィールド: name, nameReading, company, department, title, phoneNumbers(配列), emails(配列), address, website"
         }
       ]
     }]
   }
   ```

2. **顔写真の手動紐づけ（FacePhoto）— Embeddingなしの軽量版**
   - PHPickerでカメラロールから写真選択
   - VNDetectFaceRectanglesRequestで顔検出、各顔に枠を表示
   - タップで選択 → 顔部分をクロップ → 確認画面 → JPEG保存
   - PersonのfacePhotoPathに保存パスを記録
   - **CoreMLモデルやEmbeddingはPhase 3まで不要**

3. **顔写真グリッド表示**
   - PersonListに表示モード切り替えを追加
   - 顔写真が紐づいたPersonのみをグリッド表示
   - LazyVGridを使用

4. **タグ機能**
   - タグの作成・割り当て・削除
   - PersonDetail画面からタグ追加
   - 一覧画面でタグフィルタリング

5. **iPhone連絡先への片方向エクスポート（ContactService）**
   - CNContactStore, CNMutableContact を使用
   - 最新のBusinessCardの構造化データから連絡先オブジェクトを生成
   - **保存前にプレビュー画面を表示**（ユーザーが確認してから保存）
   - 既に同名の連絡先がある場合は警告（自動上書き・マージはしない）
   - **片方向のみ。同期しない。連絡先側で修正してもアプリには反映されない（逆も同様）**

6. **エクスポート（ExportService）**
   - CSV: カンマ区切り、UTF-8 BOM付き（Excel対応）
   - vCard/VCF: CNContactVCardSerialization を使用
   - タグ・イベントで絞り込んでエクスポート可能
   - UIActivityViewController で共有

7. **バックアップ・リストア（BackupService）**
   - **オープンフォーマット（SQLite + JPEG画像をZIP）**
   - アプリのデータフォルダ構造がそのままバックアップ構造と一致
   - iCloud Drive自動バックアップ（FileManager.default.url(forUbiquityContainerIdentifier:)）
   - 設定画面でON/OFF切り替え
   - 手動バックアップ: Filesアプリへの書き出し（UIDocumentPickerViewController）
   - リストア: ZIPを解凍 → SQLite読み込み + 画像復元

### Phase 3: 顔検索（v2コア機能）

1. **CoreMLモデルの組み込み**
   - MobileFaceNetのONNXモデルを `coremltools` でCoreML形式に変換
   - アプリバンドルの `MLModels/` に追加
   - FaceEmbeddingServiceを実装
   - 入力: 112x112 RGB画像 → 出力: 128次元Float配列

2. **既存の顔写真にEmbeddingを付与**
   - Phase 2で登録済みの顔写真に対してEmbeddingを一括抽出
   - PersonのfaceEmbeddingフィールドに保存
   - SwiftDataのスキーママイグレーション（faceEmbeddingフィールド追加）

3. **同一人物の写真検索（スマートスコーピング）**
   - 第1段階: Encounterのdateの前後3日間 + location周辺の写真に絞って検索
   - PHAssetの `creationDate` と `location` で絞り込み
   - Vision Frameworkで顔検出 → CoreMLで特徴量抽出 → コサイン類似度で判定
   - 第2段階: 「範囲を広げて検索」で1ヶ月→3ヶ月→1年に拡大

4. **写真からPersonを逆引き（顔→Person検索）**
   - 「写真から探す」ボタン → 写真選択 → 顔タップ → Embedding抽出
   - 全PersonのfaceEmbeddingとコサイン類似度を比較
   - 一致するPersonがあれば詳細画面へ

5. **重複検出に顔Embedding照合を追加**
   - 既存の氏名・会社名照合に加え、faceEmbeddingの類似度も判定材料に

### Phase 4: 商品化

1. **フィーチャーフラグの課金連携**

   ```swift
   @Observable
   class FeatureFlags {
       static let shared = FeatureFlags()
       
       // 開発中は全てtrue。商品化時にサブスク状態と連携
       var isAIStructuringEnabled: Bool = true
       var isFacePhotoEnabled: Bool = true
       var isFaceSearchEnabled: Bool = true
       var isReverseFaceLookupEnabled: Bool = true
       var isExportEnabled: Bool = true
       var isCloudBackupEnabled: Bool = true
       var isAdvancedTaggingEnabled: Bool = true
       
       func updateFromSubscription(_ isSubscribed: Bool) {
           // 課金対象の機能をここで制御（後日決定）
       }
   }
   ```

   - 各ViewModelでフラグを参照。無効な機能はグレーアウト + 「プレミアム機能」バッジ

2. **サブスクリプション（StoreKit 2）**
   - Product ID定義
   - 購入フロー
   - FeatureFlagsとの連携
   - レシート検証

3. **APIプロキシサーバー**
   - Akkurat運用。アプリ → プロキシ → Claude API
   - APIキーはサーバー側管理
   - サブスク有効性をサーバー側で検証
   - レート制限

4. **App Store申請（審査対策含む）**
   - スクリーンショット作成
   - プライバシーポリシーページ（akkurat.jpにホスト）
   - **Review Notes:**
     - 無料版: ネットワーク通信ゼロ
     - 有料版: AI構造化のみAPI通信、ユーザーが明示的選択
     - Anthropic APIポリシーの公式URL:
       - https://privacy.claude.com
       - https://platform.claude.com/docs/en/build-with-claude/zero-data-retention
   - **App Privacy Details** の正確な設定
   - **アプリ内透明性:** AI構造化初回利用時に説明ダイアログ

5. **多言語対応**
   - Localizable.strings に英語、中国語（簡体字/繁体字）、韓国語を追加
   - App Storeメタデータの多言語化

---

## Claude Codeへの指示テンプレート

### 開発開始時

```
このプロジェクトは ./bc/ にある名刺管理iOSアプリです。

まず以下を読んでください:
1. ./bc/docs/meishi-app-spec-v2.md（プロダクト仕様書）
2. ./bc/docs/claude-code-prompt.md（このファイル — 開発ルールと実装指示）

データモデルはPerson中心設計です（仕様書セクション6参照）。
Phase 1のステップ1から順に実装を開始してください。
UIに表示するすべての文字列はLocalizable.stringsに外出ししてください。
```

### 特定の機能を実装する場合

```
./bc/docs/claude-code-prompt.md の開発ルールに従って、
Phase X のステップ Y「（機能名）」を実装してください。

仕様の詳細は ./bc/docs/meishi-app-spec-v2.md のセクション Z を参照。
UIの文字列はすべてLocalizable.stringsに外出しすること。
```

### バグ修正・リファクタリング

```
./bc/docs/claude-code-prompt.md の開発ルールに従って、
以下の問題を修正してください:
（問題の説明）

修正後、関連するユニットテストも更新してください。
```

---

## 補足: 技術的な注意点

### SwiftData のスキーマバージョニング
- データモデルを変更する場合は `VersionedSchema` と `SchemaMigrationPlan` を定義
- Phase 3でPersonに`faceEmbedding`フィールドを追加する際にマイグレーションが必要
- Phase 1から適切に設計しておく

### Apple Vision Framework のパフォーマンス
- `VNRecognizeTextRequest` は `.accurate` レベルだと処理に1〜3秒かかる
- メインスレッドをブロックしない。必ず `Task { }` で非同期実行
- 処理中はProgressViewを表示

### Photos Framework のアクセス
- iOS 17+では `PHPhotoLibrary.requestAuthorization(for: .readWrite)` を使用
- 限定アクセス（Limited Access）にも対応する
- PHAssetの `creationDate` と `location` を顔写真検索のフィルタに使用（Phase 3）

### Claude API のエラーハンドリング
- ネットワークエラー: リトライ（最大3回、exponential backoff）
- 401 Unauthorized: APIキー無効 → ユーザーにエラー表示
- 429 Rate Limit: リトライ後にエラー表示
- レスポンスのJSONパースに失敗: 手動構造化にフォールバック
- タイムアウト: 30秒

### CoreML 顔認識モデルの準備（Phase 3）
- MobileFaceNetのONNXモデルを `coremltools` でCoreML形式に変換
  ```bash
  pip install coremltools onnx
  python -c "
  import coremltools as ct
  import onnx
  model = onnx.load('mobilefacenet.onnx')
  mlmodel = ct.converters.onnx.convert(model)
  mlmodel.save('MobileFaceNet.mlmodel')
  "
  ```
- 入力: 112x112 RGB画像 → 出力: 128次元Float配列
- コサイン類似度 >= 0.5 で同一人物と判定（閾値は要チューニング）
- モデルのライセンス（商用利用可能か）を検証すること

### バックアップのZIP生成
- 軽量ライブラリ `ZIPFoundation`（Swift Package Manager経由）を使用
- ZIP内のパス構造: `backup_YYYYMMDD/database.sqlite` + `backup_YYYYMMDD/images/*.jpg`

### 生体認証の実装
- `LAContext` を使用
- `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` で利用可否を確認
- 認証失敗時はパスコードフォールバック（`deviceOwnerAuthentication`）
- ScenePhaseの変化（`.active` → `.inactive` → `.background`）を監視し、復帰時に再認証

---

*このドキュメントのバージョン: 2.0*
*最終更新: 2026-03-23*
*仕様書バージョン: meishi-app-spec-v2.md*
