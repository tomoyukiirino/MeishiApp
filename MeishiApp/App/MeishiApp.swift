import SwiftUI
import SwiftData

// MARK: - MeishiApp

/// 名刺管理アプリのエントリポイント。
/// SwiftDataのModelContainerを設定し、生体認証を管理する。
@main
struct MeishiApp: App {
    // MARK: - Properties

    /// SwiftDataのModelContainer
    private let modelContainer: ModelContainer

    /// 認証サービス
    @State private var authService = AuthenticationService.shared

    /// シーンのフェーズ（アクティブ、バックグラウンド等）
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Initialization

    init() {
        // SwiftDataのスキーマとModelContainerを設定
        do {
            let schema = Schema([
                Person.self,
                BusinessCard.self,
                Encounter.self,
                Tag.self
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .environment(authService)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
        }
    }

    // MARK: - Private Methods

    /// シーンフェーズの変化を処理
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // バックグラウンドからアクティブに復帰した場合
            if oldPhase == .background || oldPhase == .inactive {
                // 認証が有効で、ロックされている場合は認証を要求
                // （ContentView側でロック画面を表示）
            }

        case .inactive:
            // 非アクティブになった場合（通知センター表示など）
            break

        case .background:
            // バックグラウンドに移行した場合、アプリをロック
            authService.lock()

        @unknown default:
            break
        }
    }
}

// MARK: - ContentView

/// メインコンテンツビュー。認証状態に応じてロック画面または通常画面を表示する。
struct ContentView: View {
    // MARK: - Properties

    @Environment(AuthenticationService.self) private var authService

    // MARK: - Body

    var body: some View {
        Group {
            if authService.isLocked && authService.isAuthenticationEnabled {
                LockScreenView()
            } else {
                MainTabView()
            }
        }
    }
}

// MARK: - LockScreenView

/// ロック画面。生体認証を要求する。
struct LockScreenView: View {
    // MARK: - Properties

    @Environment(AuthenticationService.self) private var authService
    @State private var errorMessage: String?
    @State private var isAuthenticating = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // アプリアイコン・タイトル
            VStack(spacing: 16) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("MeishiApp")
                    .font(.title)
                    .fontWeight(.semibold)
            }

            Spacer()

            // ロック解除ボタン
            VStack(spacing: 16) {
                Button {
                    Task {
                        await authenticate()
                    }
                } label: {
                    HStack {
                        Image(systemName: biometryIconName)
                        Text(String(localized: "auth.unlock"))
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isAuthenticating)
                .padding(.horizontal, 40)

                // エラーメッセージ
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Spacer()
        }
        .task {
            // 画面表示時に自動的に認証を開始
            await authenticate()
        }
    }

    // MARK: - Private Methods

    private func authenticate() async {
        isAuthenticating = true
        errorMessage = nil

        let result = await authService.authenticate()

        switch result {
        case .success:
            // 成功時は何もしない（ContentViewが自動的に切り替わる）
            break
        case .cancelled:
            // キャンセル時もエラー表示しない
            break
        default:
            errorMessage = result.localizedMessage
        }

        isAuthenticating = false
    }

    private var biometryIconName: String {
        switch authService.biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        default:
            return "lock"
        }
    }
}

// MARK: - MainTabView

/// メインのタブビュー。Phase 1では人の一覧のみ表示。
struct MainTabView: View {
    // MARK: - Body

    var body: some View {
        TabView {
            PersonListView()
                .tabItem {
                    Label(
                        String(localized: "person.list.title"),
                        systemImage: "person.text.rectangle"
                    )
                }

            SettingsView()
                .tabItem {
                    Label(
                        String(localized: "settings.title"),
                        systemImage: "gearshape"
                    )
                }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: [Person.self, BusinessCard.self, Encounter.self, Tag.self], inMemory: true)
        .environment(AuthenticationService.shared)
}
