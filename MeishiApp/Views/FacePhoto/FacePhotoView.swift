import SwiftUI
import PhotosUI

// MARK: - FacePhotoSelectionView

/// 顔写真選択・紐づけ画面。
/// カメラロールから写真を選択し、顔を検出して選択する。
struct FacePhotoSelectionView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Bindable var person: Person

    @State private var viewModel = FacePhotoViewModel()
    @State private var showingPhotoPicker = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.currentStep {
                case .selectPhoto:
                    photoSelectionView
                case .detectingFaces:
                    detectingFacesView
                case .selectFace:
                    faceSelectionView
                case .confirmFace:
                    faceConfirmationView
                case .saving:
                    savingView
                }
            }
            .navigationTitle(String(localized: "face.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPhotoPicker) {
                FacePhotoPicker(selectedImage: $viewModel.selectedPhoto)
            }
            .onChange(of: viewModel.selectedPhoto) { _, newPhoto in
                if newPhoto != nil {
                    Task {
                        await viewModel.detectFaces()
                    }
                }
            }
            .onChange(of: viewModel.isSaved) { _, isSaved in
                if isSaved {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Step Views

    /// 写真選択ビュー
    private var photoSelectionView: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text(String(localized: "face.select"))
                .font(.title2)
                .fontWeight(.semibold)

            Text("写真ライブラリから、この方が写っている写真を選んでください")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                showingPhotoPicker = true
            } label: {
                Label(String(localized: "capture.fromLibrary"), systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    /// 顔検出中ビュー
    private var detectingFacesView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(String(localized: "face.detecting"))
                .font(.headline)

            if let photo = viewModel.selectedPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }

    /// 顔選択ビュー
    private var faceSelectionView: some View {
        VStack(spacing: 20) {
            Text(String(localized: "face.selectFace"))
                .font(.headline)

            if let photo = viewModel.selectedPhoto {
                ZStack {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            GeometryReader { geometry in
                                ForEach(viewModel.detectedFaces) { face in
                                    let rect = face.rectInImageCoordinates(
                                        imageWidth: geometry.size.width,
                                        imageHeight: geometry.size.height
                                    )

                                    Button {
                                        viewModel.selectFace(face)
                                    } label: {
                                        Rectangle()
                                            .stroke(
                                                viewModel.selectedFace?.id == face.id ? Color.blue : Color.white,
                                                lineWidth: viewModel.selectedFace?.id == face.id ? 3 : 2
                                            )
                                            .background(Color.blue.opacity(0.1))
                                    }
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                }
                            }
                        }
                }
                .frame(maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if viewModel.detectedFaces.isEmpty {
                Text(String(localized: "face.noFaceDetected"))
                    .foregroundStyle(.orange)

                // 顔が検出されなくてもこの写真を使うオプション
                Button {
                    Task {
                        await viewModel.usePhotoWithoutFaceDetection()
                    }
                } label: {
                    Text(String(localized: "face.useThisPhoto"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)

                Button {
                    viewModel.reset()
                    showingPhotoPicker = true
                } label: {
                    Text("別の写真を選ぶ")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
            } else {
                Button {
                    Task {
                        await viewModel.cropSelectedFace()
                    }
                } label: {
                    Text(String(localized: "common.next"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.selectedFace != nil ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(viewModel.selectedFace == nil)
                .padding(.horizontal)
            }
        }
        .padding()
    }

    /// 顔確認ビュー
    private var faceConfirmationView: some View {
        VStack(spacing: 30) {
            Text(String(localized: "face.confirm"))
                .font(.headline)

            if let croppedFace = viewModel.croppedFaceImage {
                Image(uiImage: croppedFace)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }

            Text(person.name)
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 20) {
                Button {
                    viewModel.currentStep = .selectFace
                } label: {
                    Text(String(localized: "capture.retake"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    Task {
                        await viewModel.saveFacePhoto(for: person)
                    }
                } label: {
                    Text(String(localized: "common.save"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }

    /// 保存中ビュー
    private var savingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(String(localized: "common.processing"))
        }
    }
}

// MARK: - FacePhotoViewModel

/// 顔写真選択画面のViewModel。
@Observable
final class FacePhotoViewModel {
    // MARK: - Types

    enum Step {
        case selectPhoto
        case detectingFaces
        case selectFace
        case confirmFace
        case saving
    }

    // MARK: - Properties

    var currentStep: Step = .selectPhoto
    var selectedPhoto: UIImage?
    var detectedFaces: [DetectedFace] = []
    var selectedFace: DetectedFace?
    var croppedFaceImage: UIImage?
    var isSaved = false
    var errorMessage: String?

    // MARK: - Methods

    func detectFaces() async {
        guard let photo = selectedPhoto else { return }

        await MainActor.run {
            currentStep = .detectingFaces
        }

        do {
            let faces = try await FaceDetectionService.shared.detectFaces(in: photo)

            await MainActor.run {
                detectedFaces = faces
                currentStep = .selectFace

                // 顔が1つだけの場合は自動選択
                if faces.count == 1 {
                    selectedFace = faces.first
                }
            }
        } catch {
            await MainActor.run {
                detectedFaces = []
                currentStep = .selectFace
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectFace(_ face: DetectedFace) {
        selectedFace = face
    }

    func cropSelectedFace() async {
        guard let photo = selectedPhoto, let face = selectedFace else { return }

        let croppedImages = await FaceDetectionService.shared.cropFaces(
            from: photo,
            faces: [face],
            padding: 0.4
        )

        await MainActor.run {
            if let (_, croppedImage) = croppedImages.first {
                croppedFaceImage = croppedImage
                currentStep = .confirmFace
            }
        }
    }

    /// 顔検出なしで写真をそのまま使用（正方形にクロップ）
    func usePhotoWithoutFaceDetection() async {
        guard let photo = selectedPhoto else { return }

        // 写真を正方形にクロップ
        let croppedImage = await cropToSquare(photo)

        await MainActor.run {
            croppedFaceImage = croppedImage
            currentStep = .confirmFace
        }
    }

    /// 画像を正方形にクロップ（中央から）
    private func cropToSquare(_ image: UIImage) async -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let size = min(width, height)

        let x = (width - size) / 2
        let y = (height - size) / 2

        let cropRect = CGRect(x: x, y: y, width: size, height: size)

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return image }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    @MainActor
    func saveFacePhoto(for person: Person) async {
        guard let faceImage = croppedFaceImage else { return }

        currentStep = .saving

        do {
            // 既存の顔写真を削除
            if person.facePhotoPath != nil {
                try await ImageStorageService.shared.deleteFacePhoto(personId: person.id)
            }

            // 新しい顔写真を保存
            let path = try await ImageStorageService.shared.saveFacePhoto(faceImage, personId: person.id)

            person.facePhotoPath = path
            person.updatedAt = Date()
            isSaved = true
        } catch {
            errorMessage = error.localizedDescription
            currentStep = .confirmFace
        }
    }

    func reset() {
        currentStep = .selectPhoto
        selectedPhoto = nil
        detectedFaces = []
        selectedFace = nil
        croppedFaceImage = nil
        errorMessage = nil
    }
}

// MARK: - FacePhotoPicker

/// 顔写真用のフォトピッカー。
struct FacePhotoPicker: UIViewControllerRepresentable {
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
        let parent: FacePhotoPicker

        init(_ parent: FacePhotoPicker) {
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

// MARK: - FacePhotoButton

/// PersonDetail画面に表示する顔写真追加/変更ボタン。
struct FacePhotoButton: View {
    @Bindable var person: Person
    @State private var showingFacePhotoSelection = false
    @State private var showingRemoveConfirmation = false
    @State private var faceImage: UIImage?

    var body: some View {
        Menu {
            if person.hasFacePhoto {
                Button {
                    showingFacePhotoSelection = true
                } label: {
                    Label(String(localized: "face.change"), systemImage: "arrow.triangle.2.circlepath")
                }

                Button(role: .destructive) {
                    showingRemoveConfirmation = true
                } label: {
                    Label(String(localized: "face.remove"), systemImage: "trash")
                }
            } else {
                Button {
                    showingFacePhotoSelection = true
                } label: {
                    Label(String(localized: "face.add"), systemImage: "plus")
                }
            }
        } label: {
            ZStack {
                if let faceImage = faceImage {
                    Image(uiImage: faceImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.title)
                                .foregroundStyle(.gray)
                        }
                }
            }
            .frame(width: 100, height: 100)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .background(Color.white.clipShape(Circle()))
            }
        }
        .sheet(isPresented: $showingFacePhotoSelection) {
            FacePhotoSelectionView(person: person)
        }
        .confirmationDialog(
            String(localized: "face.remove"),
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                Task {
                    await removeFacePhoto()
                }
            }
        }
        .task {
            await loadFaceImage()
        }
        .onChange(of: person.facePhotoPath) { _, _ in
            Task {
                await loadFaceImage()
            }
        }
    }

    private func loadFaceImage() async {
        guard let path = person.facePhotoPath else {
            faceImage = nil
            return
        }
        faceImage = await ImageStorageService.shared.loadImage(relativePath: path)
    }

    private func removeFacePhoto() async {
        do {
            try await ImageStorageService.shared.deleteFacePhoto(personId: person.id)
            await MainActor.run {
                person.facePhotoPath = nil
                person.updatedAt = Date()
                faceImage = nil
            }
        } catch {
            // エラー処理
        }
    }
}

// MARK: - Preview

#Preview {
    FacePhotoSelectionView(person: Person(name: "山田太郎"))
}
