import SwiftUI
import PhotosUI

final class FaceStudioModel: ObservableObject {
    enum Stage: Equatable { case pick, working, review, failed(String) }

    struct Step: Identifiable {
        let id: Int
        let title: String
        var done = false
    }

    static let stepTitles = [
        "Finding the face",
        "Mapping 76 facial landmarks",
        "Cutting out the background",
        "Sculpting a 3D head to match",
        "Wrapping skin & painting hair",
    ]

    @Published var stage: Stage = .pick
    @Published var photo: UIImage?
    @Published var steps: [Step] = []
    @Published var landmarks: [CGPoint] = []
    @Published var faceBox: CGRect = .zero
    @Published var warnings: [String] = []
    @Published var name = ""
    @Published var hat: HatStyle = .none { didSet { refreshPreview() } }
    @Published var hair: HairVolume = .none { didSet { refreshPreview() } }
    @Published var googly = false { didSet { refreshPreview() } }

    let preview = ShowcaseStage(character: nil, sway: false)
    private var built: BuiltFace?
    private let draftID = UUID()

    func process(_ image: UIImage) {
        photo = image
        stage = .working
        steps = Self.stepTitles.enumerated().map { Step(id: $0.offset, title: $0.element) }
        landmarks = []
        warnings = []
        built = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let capture = try FaceAnalyzer.analyze(image)
                DispatchQueue.main.async {
                    self.faceBox = capture.overlayBox
                    withAnimation(.easeOut(duration: 0.6)) { self.landmarks = capture.overlayPoints }
                    self.markDone(0)
                }
                let face = FaceTextureBuilder.build(from: capture)
                let character = self.makeCharacter(face)
                _ = HeadGeometryCache.output(for: character)   // sculpt off the main thread

                var warnings: [String] = []
                if abs(capture.yaw) > 0.35 { warnings.append("Their face is turned — a straight-on photo looks best.") }
                if abs(capture.roll) > 0.5 { warnings.append("Photo is tilted a lot. We straightened it, but results may vary.") }
                if capture.faceCount > 1 { warnings.append("Found \(capture.faceCount) faces — we used the biggest one.") }
                if capture.personMask == nil { warnings.append("Couldn't separate the background, so edges may look busy.") }

                DispatchQueue.main.async {
                    self.built = face
                    self.warnings = warnings
                    // Reveal the remaining steps with a little rhythm.
                    for i in 1..<Self.stepTitles.count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * Double(i)) { self.markDone(i) }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * Double(Self.stepTitles.count) + 0.3) {
                        self.preview.show(character)
                        withAnimation(.spring) { self.stage = .review }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    withAnimation { self.stage = .failed(error.localizedDescription) }
                }
            }
        }
    }

    private func markDone(_ i: Int) {
        guard i < steps.count else { return }
        withAnimation(.spring) { steps[i].done = true }
    }

    private func makeCharacter(_ face: BuiltFace) -> GameCharacter {
        let shirts: [[Float]] = [[0.95, 0.3, 0.5], [0.2, 0.6, 0.95], [0.98, 0.75, 0.15], [0.3, 0.8, 0.5], [0.6, 0.3, 0.9]]
        let meta = CharacterMeta(id: draftID, name: name.isEmpty ? "Mystery Guest" : name, tagline: "Custom big head",
                                 shape: face.shape, hat: hat, hairVolume: hair, googlyEyes: googly,
                                 skinRGB: face.skin.rgbArray, hairRGB: face.hair.rgbArray,
                                 shirtRGB: shirts.randomElement()!, isDefault: false, createdAt: Date())
        return GameCharacter(meta: meta, texture: face.texture)
    }

    private func refreshPreview() {
        guard stage == .review, let built else { return }
        preview.show(makeCharacter(built), animated: false)
    }

    func save(to store: CharacterStore) {
        guard let built else { return }
        var meta = makeCharacter(built).meta
        meta.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Mystery Guest" : name.trimmingCharacters(in: .whitespaces)
        meta.id = UUID()
        store.add(meta: meta, texture: built.texture)
    }

    func reset() {
        stage = .pick
        photo = nil
        landmarks = []
    }
}

struct FaceStudioView: View {
    /// Debug/CI only: a photo to process as soon as the studio opens.
    var testImage: UIImage?
    @EnvironmentObject private var store: CharacterStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = FaceStudioModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 16) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title) }
                    Spacer()
                    Text("Face Studio").font(.party(24))
                    Spacer()
                    Color.clear.frame(width: 30, height: 30)
                }
                .padding(.horizontal)
                switch model.stage {
                case .pick: pickView
                case .working: workingView
                case .review: reviewView
                case .failed(let message): failedView(message)
                }
            }
            .padding(.top, 10)
        }
        .onAppear {
            if let testImage, model.stage == .pick { model.process(testImage) }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await MainActor.run { model.process(image) }
                }
                await MainActor.run { pickerItem = nil }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(isPresented: $showCamera) { image in model.process(image) }.ignoresSafeArea()
        }
    }

    // MARK: Pick

    private var pickView: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Theme.pink.opacity(0.2)).frame(width: 220, height: 220)
                Image(systemName: "face.dashed").font(.system(size: 110, weight: .light)).foregroundStyle(Theme.yellow)
            }
            Text("Who's getting the big-head treatment?").font(.party(24)).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                Label("Face the camera, eyes open", systemImage: "eye")
                Label("Good, even light — no heavy shadows", systemImage: "sun.max")
                Label("No sunglasses or hands on the face", systemImage: "eyeglasses")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            Spacer()
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose a Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(ChunkyButtonStyle())
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Take a Photo", systemImage: "camera.fill") }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.yellow, textColor: .black))
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 30)
    }

    // MARK: Working

    private var workingView: some View {
        VStack(spacing: 20) {
            if let photo = model.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        GeometryReader { geo in
                            let size = geo.size
                            ZStack(alignment: .topLeading) {
                                if model.faceBox != .zero {
                                    Rectangle()
                                        .stroke(Theme.yellow, lineWidth: 2)
                                        .frame(width: model.faceBox.width * size.width, height: model.faceBox.height * size.height)
                                        .offset(x: model.faceBox.minX * size.width, y: model.faceBox.minY * size.height)
                                }
                                ForEach(Array(model.landmarks.enumerated()), id: \.offset) { _, p in
                                    Circle().fill(Theme.teal)
                                        .frame(width: 5, height: 5)
                                        .offset(x: p.x * size.width - 2.5, y: p.y * size.height - 2.5)
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .frame(maxHeight: 360)
                    .padding(.horizontal)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.steps) { step in
                    HStack(spacing: 12) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundStyle(step.done ? Theme.teal : .white.opacity(0.5))
                            .font(.title3)
                            .symbolEffect(.pulse, isActive: !step.done)
                        Text(step.title).font(.headline).opacity(step.done ? 1 : 0.6)
                    }
                }
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: Review

    private var reviewView: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 28).fill(RadialGradient(colors: [Theme.pink.opacity(0.5), Theme.deep], center: .center, startRadius: 10, endRadius: 240))
                SceneContainer(scene: model.preview.scene, pointOfView: model.preview.camera, allowsCameraControl: true)
                HStack(spacing: 8) {
                    expressionButton("Pie", "birthday.cake") { model.preview.throwPie() }
                    expressionButton("Squish", "hand.raised") { model.preview.react(.squish) }
                    expressionButton("Bonk", "hand.point.right") { model.preview.react(.skewRight) }
                    expressionButton("Puff", "wind") { model.preview.react(.puff) }
                    expressionButton("Yell", "mouth") { model.preview.react(.mouthOpen) }
                }
                .padding(.bottom, 10)
            }
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal)
            Text("Drag to spin them around").font(.caption).foregroundStyle(.white.opacity(0.6))

            ForEach(model.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.yellow)
                    .padding(.horizontal)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Who is this? (e.g. Uncle Ray)", text: $model.name)
                        .font(.headline)
                        .padding(14)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    Text("Hat").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(HatStyle.allCases) { h in
                                chip(h.label, symbol: h.symbol, selected: model.hat == h) { model.hat = h }
                            }
                        }
                    }
                    Text("Hair").font(.headline)
                    HStack {
                        ForEach(HairVolume.allCases) { h in
                            chip(h.label, symbol: nil, selected: model.hair == h) { model.hair = h }
                        }
                    }
                    Toggle(isOn: $model.googly) { Text("Googly eyes 👀").font(.headline) }
                        .tint(Theme.pink)
                }
                .padding(.horizontal, 20)
            }
            HStack(spacing: 12) {
                Button("Retake") { model.reset() }
                    .buttonStyle(ChunkyButtonStyle(color: .gray))
                    .frame(width: 130)
                Button("Add to Cast") {
                    model.save(to: store)
                    dismiss()
                }
                .buttonStyle(ChunkyButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private func expressionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                Text(title).font(.caption2.weight(.heavy))
            }
            .frame(width: 56, height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(.white)
    }

    private func chip(_ title: String, symbol: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(selected ? Theme.pink : .white.opacity(0.1), in: Capsule())
        }
        .foregroundStyle(.white)
    }

    // MARK: Failed

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "face.dashed.fill").font(.system(size: 90)).foregroundStyle(Theme.pink)
            Text("Hmm, that didn't work").font(.party(26))
            Text(message).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Button("Try another photo") { model.reset() }.buttonStyle(ChunkyButtonStyle())
        }
        .padding(30)
    }
}

/// UIKit camera wrapper (front camera by default — selfies welcome).
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.isPresented = false }
    }
}
