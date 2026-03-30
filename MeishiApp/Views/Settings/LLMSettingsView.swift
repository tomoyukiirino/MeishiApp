import SwiftUI

// MARK: - LLMSettingsView

/// LLM（AI構造化）設定画面
struct LLMSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = LLMSettingsManager.shared

    @State private var showingAPIKeyInput = false
    @State private var showingAIDisclosure = false
    @State private var selectedProviderForKeyInput: LLMProvider?

    var body: some View {
        List {
            // 接続モードセクション
            connectionModeSection

            // プロバイダー選択セクション（selfApiKeyモードの場合のみ）
            if settings.connectionMode == .selfApiKey {
                providerSelectionSection

                // プライバシーモードセクション
                privacyModeSection
            }

            // AI利用説明セクション
            aiDisclosureSection
        }
        .navigationTitle(String(localized: "settings.aiStructuring"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAIDisclosure) {
            AIDisclosureView {
                showingAIDisclosure = false
            }
        }
        .sheet(item: $selectedProviderForKeyInput) { provider in
            LLMAPIKeyInputView(provider: provider)
        }
    }

    // MARK: - Sections

    /// 接続モードセクション
    private var connectionModeSection: some View {
        Section {
            ForEach(LLMConnectionMode.allCases, id: \.self) { mode in
                // Akkuratサブスクリプションは現在無効
                if mode != .akkuratSubscription {
                    Button {
                        settings.connectionMode = mode
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.localizedName)
                                    .foregroundStyle(.primary)
                                Text(mode.localizedDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if settings.connectionMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        } header: {
            Text(String(localized: "llm.connectionMode"))
        } footer: {
            Text(String(localized: "llm.connectionMode.footer"))
        }
    }

    /// プロバイダー選択セクション
    private var providerSelectionSection: some View {
        Section {
            ForEach(LLMProvider.allCases, id: \.self) { provider in
                Button {
                    settings.selectedProvider = provider
                } label: {
                    HStack {
                        Image(systemName: provider.iconName)
                            .foregroundStyle(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.displayName)
                                .foregroundStyle(.primary)

                            // APIキー状態
                            if KeychainService.shared.hasAPIKey(for: provider) {
                                if let masked = KeychainService.shared.getMaskedAPIKey(for: provider) {
                                    Text(masked)
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            } else {
                                Text(String(localized: "llm.apiKey.notSet"))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            // 画像サポート表示
                            if !provider.supportsImageInput {
                                Text(String(localized: "llm.provider.textOnly"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        // 選択状態
                        if settings.selectedProvider == provider {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }

                        // APIキー設定ボタン
                        Button {
                            selectedProviderForKeyInput = provider
                        } label: {
                            Image(systemName: "key")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text(String(localized: "llm.provider"))
        } footer: {
            if !settings.hasCurrentProviderAPIKey {
                Text(String(localized: "llm.provider.needsApiKey"))
                    .foregroundStyle(.orange)
            }
        }
    }

    /// プライバシーモードセクション
    private var privacyModeSection: some View {
        Section {
            ForEach(LLMPrivacyMode.allCases, id: \.self) { mode in
                let isDisabled = mode == .accuracyFirst && !settings.currentProviderSupportsImage

                Button {
                    if !isDisabled {
                        settings.privacyMode = mode
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(mode.localizedName)
                                    .foregroundStyle(isDisabled ? .secondary : .primary)

                                if isDisabled {
                                    Text(String(localized: "llm.mode.notSupported"))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }

                            Text(mode.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if settings.privacyMode == mode && !isDisabled {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .disabled(isDisabled)
            }
        } header: {
            Text(String(localized: "settings.aiMode"))
        }
    }

    /// AI利用説明セクション
    private var aiDisclosureSection: some View {
        Section {
            Button {
                showingAIDisclosure = true
            } label: {
                HStack {
                    Label {
                        Text(String(localized: "settings.aiDisclosure"))
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - LLMAPIKeyInputView

/// LLM APIキー入力画面
struct LLMAPIKeyInputView: View {
    @Environment(\.dismiss) private var dismiss

    let provider: LLMProvider

    @State private var inputKey: String = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(provider.apiKeyPlaceholder, text: $inputKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(String(localized: "llm.apiKey.title \(provider.displayName)"))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "llm.apiKey.description"))

                        if let helpURL = provider.apiKeyHelpURL {
                            Link(destination: helpURL) {
                                HStack {
                                    Text(String(localized: "llm.apiKey.getKey"))
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .font(.caption)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        Task {
                            await testAPIKey()
                        }
                    } label: {
                        HStack {
                            Text(String(localized: "llm.apiKey.test"))
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else if let result = testResult {
                                switch result {
                                case .success:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                case .failure:
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .disabled(inputKey.isEmpty || isTesting)

                    if case .failure(let message) = testResult {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if KeychainService.shared.hasAPIKey(for: provider) {
                    Section {
                        Button(role: .destructive) {
                            KeychainService.shared.deleteAPIKey(for: provider)
                            inputKey = ""
                            testResult = nil
                            dismiss()
                        } label: {
                            Text(String(localized: "llm.apiKey.delete"))
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "llm.apiKey.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) {
                        saveAPIKey()
                    }
                    .disabled(inputKey.isEmpty)
                }
            }
            .onAppear {
                inputKey = KeychainService.shared.getAPIKey(for: provider) ?? ""
            }
        }
    }

    private func saveAPIKey() {
        if inputKey.isEmpty {
            KeychainService.shared.deleteAPIKey(for: provider)
        } else {
            KeychainService.shared.saveAPIKey(inputKey, for: provider)
        }
        dismiss()
    }

    private func testAPIKey() async {
        isTesting = true
        testResult = nil

        // テスト用にアダプターを作成
        let adapter = LLMServiceFactory.shared.createAdapter(for: provider, apiKey: inputKey)

        do {
            // 簡単なテストリクエスト
            _ = try await adapter.structureFromText("テスト名刺")
            await MainActor.run {
                testResult = .success
            }
        } catch let error as LLMServiceError {
            await MainActor.run {
                switch error {
                case .unauthorized:
                    testResult = .failure(String(localized: "llm.apiKey.invalid"))
                case .rateLimited:
                    testResult = .failure(String(localized: "error.rateLimit"))
                case .networkError:
                    testResult = .failure(String(localized: "error.network"))
                default:
                    testResult = .failure(error.localizedDescription ?? String(localized: "error.generic"))
                }
            }
        } catch {
            await MainActor.run {
                testResult = .failure(error.localizedDescription)
            }
        }

        isTesting = false
    }
}

// MARK: - LLMProvider Identifiable

extension LLMProvider: Identifiable {
    var id: String { rawValue }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LLMSettingsView()
    }
}
