import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - CardCaptureView

/// 名刺撮影・取り込み画面。
/// カメラで撮影またはカメラロールから選択できる。
struct CardCaptureView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = CardCaptureViewModel()
    @State private var showingImagePicker = false
    @State private var showingBackPrompt = false
    @State private var showingRegistration = false
    @State private var showingCamera = false
    @State private var showingOrientationPreview = false
    @State private var isCameraAvailable = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if showingCamera {
                    // カメラモード
                    cameraView
                } else {
                    // 選択画面
                    sourceSelectionView
                }

                // 処理中オーバーレイ
                if viewModel.isProcessing {
                    processingOverlay
                }
            }
            .navigationTitle(String(localized: "capture.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        if showingCamera {
                            showingCamera = false
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                PhotoPicker(selectedImage: $viewModel.selectedImage)
            }
            .sheet(isPresented: $showingBackPrompt, onDismiss: {
                // 裏面をスキップした場合、登録画面へ進む
                if viewModel.capturedFrontImage != nil && !viewModel.isCapturingBack {
                    showingRegistration = true
                }
            }) {
                BackCapturePromptView(viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $showingRegistration) {
                if let frontImage = viewModel.capturedFrontImage {
                    CardRegistrationView(
                        frontImage: frontImage,
                        backImage: viewModel.capturedBackImage
                    )
                }
            }
            .onChange(of: viewModel.selectedImage) { _, newImage in
                if let image = newImage {
                    Task {
                        await viewModel.processSelectedImage(image)
                    }
                }
            }
            .onChange(of: viewModel.previewImage) { _, newImage in
                // クロップ後のプレビュー画像が準備できたら、向き確認画面を表示
                if newImage != nil {
                    showingOrientationPreview = true
                }
            }
            .onChange(of: viewModel.capturedFrontImage) { _, newImage in
                if newImage != nil {
                    if viewModel.isCapturingBack {
                        showingRegistration = true
                    } else {
                        showingBackPrompt = true
                    }
                }
            }
            .onChange(of: viewModel.capturedBackImage) { _, newImage in
                // 裏面がライブラリから追加された場合、登録画面へ
                if newImage != nil && viewModel.isCapturingBack && viewModel.backCaptureMethod == .library {
                    showingRegistration = true
                }
            }
            .sheet(isPresented: $showingOrientationPreview) {
                OrientationPreviewView(viewModel: viewModel)
            }
            .task {
                await viewModel.checkCameraAuthorization()
                isCameraAvailable = AVCaptureDevice.default(for: .video) != nil
            }
        }
    }

    // MARK: - Source Selection View

    /// ソース選択画面（カメラ or ライブラリ）
    private var sourceSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()

            // アイコン
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(String(localized: "capture.selectSource"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(localized: "capture.selectSource.description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // 選択ボタン
            VStack(spacing: 16) {
                // カメラで撮影
                Button {
                    if viewModel.isCameraAuthorized {
                        showingCamera = true
                    } else {
                        Task {
                            await viewModel.requestCameraAuthorization()
                            if viewModel.isCameraAuthorized {
                                showingCamera = true
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                        Text(String(localized: "capture.useCamera"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isCameraAvailable ? Color.accentColor : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!isCameraAvailable)

                if !isCameraAvailable {
                    Text(String(localized: "capture.cameraUnavailable"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // ライブラリから選択
                Button {
                    showingImagePicker = true
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                        Text(String(localized: "capture.fromLibrary"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Camera View

    /// カメラビュー
    private var cameraView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isCameraAuthorized {
                cameraContent
            } else {
                cameraPermissionView
            }
        }
    }

    // MARK: - Subviews

    /// カメラコンテンツ
    private var cameraContent: some View {
        VStack(spacing: 0) {
            // カメラプレビュー
            CameraPreviewView(session: viewModel.captureSession)
                .overlay {
                    // 名刺ガイドフレーム
                    cardGuideOverlay
                }

            // コントロールエリア
            controlsArea
        }
    }

    /// 名刺のガイドオーバーレイ
    private var cardGuideOverlay: some View {
        GeometryReader { geometry in
            let cardWidth = geometry.size.width * 0.85
            let cardHeight = cardWidth * 0.55 // 名刺のアスペクト比

            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: cardWidth, height: cardHeight)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

            Text(String(localized: "capture.instruction"))
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .clipShape(Capsule())
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + cardHeight / 2 + 30)
        }
    }

    /// コントロールエリア
    private var controlsArea: some View {
        HStack {
            // ライブラリから選択
            Button {
                showingImagePicker = true
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
            }
            .accessibilityLabel(String(localized: "capture.fromLibrary"))

            Spacer()

            // シャッターボタン
            Button {
                Task {
                    await viewModel.capturePhoto()
                }
            } label: {
                Circle()
                    .fill(Color.white)
                    .frame(width: 70, height: 70)
                    .overlay {
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 80, height: 80)
                    }
            }
            .disabled(viewModel.isProcessing)
            .accessibilityLabel(String(localized: "capture.takePhoto"))

            Spacer()

            // カメラ切り替え（将来用のプレースホルダー）
            Color.clear
                .frame(width: 60, height: 60)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
        .background(Color.black)
    }

    /// 処理中オーバーレイ
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text(viewModel.processingPhase.localizedDescription)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(Color(.systemGray5).opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    /// カメラ権限要求ビュー
    private var cameraPermissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera")
                .font(.system(size: 60))
                .foregroundStyle(.gray)

            Text(String(localized: "capture.cameraPermission.title"))
                .font(.title2)
                .foregroundStyle(.white)

            Text(String(localized: "capture.cameraPermission.message"))
                .font(.body)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(String(localized: "capture.openSettings"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // ライブラリから選択のオプション
            Button {
                showingImagePicker = true
            } label: {
                Text(String(localized: "capture.fromLibrary"))
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
            .padding(.top)
        }
    }
}

// MARK: - BackCapturePromptView

/// 裏面撮影の確認ダイアログ。
struct BackCapturePromptView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: CardCaptureViewModel

    @State private var showingBackImagePicker = false
    private var isCameraAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 撮影済みの表面プレビュー
                if let frontImage = viewModel.capturedFrontImage {
                    Image(uiImage: frontImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 4)
                }

                Text(String(localized: "capture.captureBack"))
                    .font(.headline)

                // 裏面追加オプション
                VStack(spacing: 12) {
                    // カメラで撮影
                    Button {
                        viewModel.prepareBackCapture()
                        viewModel.backCaptureMethod = .camera
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text(String(localized: "capture.useCamera"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isCameraAvailable ? Color.accentColor : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(!isCameraAvailable)

                    // ライブラリから選択
                    Button {
                        showingBackImagePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text(String(localized: "capture.fromLibrary"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // 表面のみで完了
                    Button {
                        viewModel.skipBackCapture()
                        dismiss()
                    } label: {
                        Text(String(localized: "capture.captureBack.no"))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.clear)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle(String(localized: "capture.title"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingBackImagePicker) {
                PhotoPicker(selectedImage: Binding(
                    get: { nil },
                    set: { image in
                        if let image = image {
                            viewModel.prepareBackCapture()
                            viewModel.backCaptureMethod = .library
                            Task {
                                await viewModel.processBackImage(image)
                            }
                            dismiss()
                        }
                    }
                ))
            }
        }
    }
}

// MARK: - CameraPreviewView

/// カメラプレビューを表示するUIViewRepresentable。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        context.coordinator.previewLayer = previewLayer

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - PhotoPicker

/// 写真ライブラリから画像を選択するピッカー。
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else { return }

            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image
                    }
                }
            }
        }
    }
}

// MARK: - CardCaptureViewModel

/// 裏面取得方法
enum BackCaptureMethod {
    case camera
    case library
}

/// 画像処理の段階。
enum ImageProcessingPhase: Equatable {
    case none
    case processing

    var localizedDescription: String {
        switch self {
        case .none:
            return ""
        case .processing:
            return String(localized: "common.processing")
        }
    }
}

/// 名刺撮影画面のViewModel。
@Observable
final class CardCaptureViewModel {
    // MARK: - Properties

    var isCameraAuthorized = false
    var isProcessing = false
    var processingPhase: ImageProcessingPhase = .none
    var isCapturingBack = false
    var backCaptureMethod: BackCaptureMethod = .camera

    /// クロップ後のプレビュー画像（向き確認用）
    var previewImage: UIImage?

    var capturedFrontImage: UIImage?
    var capturedBackImage: UIImage?
    var selectedImage: UIImage?

    let captureSession = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput?

    // MARK: - Camera Authorization

    func checkCameraAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraAuthorized = true
            await setupCaptureSession()
        case .notDetermined:
            // 未決定の場合は何もしない（requestCameraAuthorizationで処理）
            isCameraAuthorized = false
        default:
            isCameraAuthorized = false
        }
    }

    func requestCameraAuthorization() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            isCameraAuthorized = granted
        }
        if granted {
            await setupCaptureSession()
        }
    }

    // MARK: - Capture Session Setup

    private func setupCaptureSession() async {
        captureSession.beginConfiguration()

        // 入力設定
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // 出力設定
        let output = AVCapturePhotoOutput()
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            photoOutput = output
        }

        captureSession.commitConfiguration()

        // セッション開始
        await MainActor.run {
            captureSession.startRunning()
        }
    }

    // MARK: - Photo Capture

    func capturePhoto() async {
        guard photoOutput != nil else { return }

        isProcessing = true

        // 写真キャプチャデリゲートを使用
        // 簡略化のため、実際の実装ではAVCapturePhotoCaptureDelegate経由で画像を取得
        // ここではプレースホルダーとして動作確認用の実装
        _ = AVCapturePhotoSettings()

        await MainActor.run {
            isProcessing = false
            // 実際の実装では、撮影した画像をcapturedFrontImage/capturedBackImageに設定
        }
    }

    // MARK: - Image Processing

    func processSelectedImage(_ image: UIImage) async {
        isProcessing = true
        processingPhase = .processing

        do {
            // EXIF補正を適用
            let normalizedImage = ImageProcessor.shared.normalizeOrientationSync(image: image)

            // 矩形検出とクロップ
            let croppedImage = try await ImageProcessor.shared.autoCropAndCorrect(image: normalizedImage)

            await MainActor.run {
                // プレビュー画像を設定（向き確認画面を表示）
                previewImage = croppedImage
                processingPhase = .none
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                // エラー時は元の画像を使用（EXIF補正のみ適用）
                let normalizedImage = ImageProcessor.shared.normalizeOrientationSync(image: image)
                previewImage = normalizedImage
                processingPhase = .none
                isProcessing = false
            }
        }
    }

    /// 裏面画像を処理（ライブラリから選択した場合）
    func processBackImage(_ image: UIImage) async {
        isProcessing = true
        processingPhase = .processing

        do {
            // EXIF補正を適用
            let normalizedImage = ImageProcessor.shared.normalizeOrientationSync(image: image)

            // 矩形検出とクロップ
            let croppedImage = try await ImageProcessor.shared.autoCropAndCorrect(image: normalizedImage)

            await MainActor.run {
                previewImage = croppedImage
                processingPhase = .none
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                let normalizedImage = ImageProcessor.shared.normalizeOrientationSync(image: image)
                previewImage = normalizedImage
                processingPhase = .none
                isProcessing = false
            }
        }
    }

    /// プレビュー画像を回転
    func rotatePreviewImage() {
        guard let image = previewImage else { return }
        previewImage = ImageProcessor.shared.rotateClockwise90Sync(image: image)
    }

    /// 向きを確定して次へ進む
    func confirmOrientation() {
        guard let image = previewImage else { return }

        if isCapturingBack {
            capturedBackImage = image
        } else {
            capturedFrontImage = image
        }

        // プレビュー画像をクリア
        previewImage = nil
    }

    // MARK: - Flow Control

    func skipBackCapture() {
        // 裏面なしで登録画面へ
        capturedBackImage = nil
        isCapturingBack = false
    }

    func prepareBackCapture() {
        isCapturingBack = true
    }

    func reset() {
        capturedFrontImage = nil
        capturedBackImage = nil
        previewImage = nil
        selectedImage = nil
        isCapturingBack = false
        isProcessing = false
    }
}

// MARK: - OrientationPreviewView

/// 向き確認・手動回転プレビュー画面。
struct OrientationPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: CardCaptureViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // 名刺画像プレビュー
                if let image = viewModel.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 8)
                        .padding(.horizontal, 24)
                }

                // 説明テキスト
                Text(String(localized: "capture.orientationHint"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // 回転ボタン
                Button {
                    viewModel.rotatePreviewImage()
                } label: {
                    HStack {
                        Image(systemName: "rotate.right")
                            .font(.title2)
                        Text(String(localized: "capture.rotate"))
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
                }

                Spacer()

                // 確定ボタン
                Button {
                    viewModel.confirmOrientation()
                    dismiss()
                } label: {
                    Text(String(localized: "capture.confirmOrientation"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .navigationTitle(String(localized: "capture.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        viewModel.previewImage = nil
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CardCaptureView()
}
