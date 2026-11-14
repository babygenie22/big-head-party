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
        "Touching up the lighting",
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

    /// Side photos added so far (at most one per side), lined up with the head.
    @Published private(set) var sides: [(view: SideView, texture: UIImage)] = []
    /// Side photos still being lined up. Saving waits for them.
    @Published private(set) var sidesInFlight = 0
    var sideBusy: Bool { sidesInFlight > 0 }
    @Published var sideMessage: String?
    /// Side photos from the face scan, waiting for the head to be built from the front photo.
    private var pendingSides: [UIImage] = []

    let preview = ShowcaseStage(character: nil, sway: false)
    private var built: BuiltFace?
    private let draftID = UUID()

    /// `depth` is the face's measured shape, when the photo came with one (TrueDepth camera or a
    /// Portrait-mode photo). `sides` are side photos taken along with it (the face scan); they
    /// are added once the head is built.
    func process(_ image: UIImage, depth: FaceDepth? = nil, sides scanned: [UIImage] = []) {
        var depth = depth
        #if DEBUG
        if depth == nil, let path = UserDefaults.standard.string(forKey: "studioTestDepth") { depth = FaceDepth.debugLoad(path) }
        #endif
        photo = image
        stage = .working
        steps = Self.stepTitles.enumerated().map { Step(id: $0.offset, title: $0.element) }
        landmarks = []
        warnings = []
        built = nil
        sides = []
        sideMessage = nil
        pendingSides = scanned
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let capture = try FaceAnalyzer.analyze(image, depth: depth)
                DispatchQueue.main.async {
                    self.faceBox = capture.overlayBox
                    withAnimation(.easeOut(duration: 0.6)) { self.landmarks = capture.overlayPoints }
                    self.markDone(0)
                }
                let face = FaceTextureBuilder.build(from: capture)
                #if targetEnvironment(simulator)
                if let out = UserDefaults.standard.string(forKey: "studioDumpTexture") {
                    try? face.texture.pngData()?.write(to: URL(fileURLWithPath: out))
                    // Shape and colors beside it, for baking photo faces into the default cast.
                    let info = DefaultCast.PhotoFace(shape: face.shape, skinRGB: face.skin.rgbArray, hairRGB: face.hair.rgbArray)
                    try? JSONEncoder().encode(info).write(to: URL(fileURLWithPath: out + ".json"))
                }
                #endif
                #if DEBUG
                Self.dumpDebug(capture: capture, face: face)
                #endif
                let character = self.makeCharacter(face)
                _ = HeadGeometryCache.output(for: character)   // sculpt off the main thread

                var warnings: [String] = []
                if abs(capture.yaw) > 0.35 { warnings.append("Their face is turned — a straight-on photo looks best.") }
                if abs(capture.roll) > 0.5 { warnings.append("Photo is tilted a lot. We straightened it, but results may vary.") }
                if capture.estimated { warnings.append("We couldn't map every feature, so the face shape is estimated. A sharper, front-facing photo works best.") }
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
                        self.debugTurn()
                        #if DEBUG
                        // `-studioSpin 90` shows the result from the side.
                        if let deg = UserDefaults.standard.string(forKey: "studioSpin"), let d = Float(deg) {
                            self.preview.turn(to: d * .pi / 180)
                        }
                        #endif
                        withAnimation(.spring) { self.stage = .review }
                        let scanned = self.pendingSides
                        self.pendingSides = []
                        scanned.forEach { self.addSide($0) }
                        #if DEBUG
                        // `-studioTestSides a.jpg,b.jpg` adds side photos straight away (simulator checks).
                        for path in (UserDefaults.standard.string(forKey: "studioTestSides") ?? "").split(separator: ",").map(String.init) {
                            if let image = UIImage(contentsOfFile: path) { self.addSide(image, testPath: path) }
                        }
                        #endif
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    withAnimation { self.stage = .failed(error.localizedDescription) }
                }
            }
        }
    }

    #if DEBUG
    /// CI only: next to the `-studioTestImage` photo, write what the AI measured so a failed
    /// head can be diagnosed without a device (texture, landmark overlay, shape JSON).
    private static func dumpDebug(capture: FaceCapture, face: BuiltFace) {
        guard let path = UserDefaults.standard.string(forKey: "studioTestImage") else { return }
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? face.texture.pngData()?.write(to: dir.appendingPathComponent("debug-texture.png"))
        let w = CGFloat(capture.image.width), h = CGFloat(capture.image.height)
        let overlay = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            UIImage(cgImage: capture.image).draw(at: .zero)
            func dot(_ p: CGPoint, _ c: UIColor, _ r: CGFloat) { c.setFill(); ctx.fill(CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)) }
            for p in capture.overlayPoints { dot(CGPoint(x: p.x * w, y: p.y * h), .cyan, 3) }
            // Vision coordinates are bottom-up; flip for drawing.
            let flip = { (p: CGPoint) in CGPoint(x: p.x, y: h - p.y) }
            capture.contour.forEach { dot(flip($0), .yellow, 5) }
            capture.nose.forEach { dot(flip($0), .green, 5) }
            capture.outerLips.forEach { dot(flip($0), .magenta, 5) }
            dot(flip(capture.eyes.0), .red, 8); dot(flip(capture.eyes.1), .red, 8)
        }
        try? overlay.pngData()?.write(to: dir.appendingPathComponent("debug-landmarks.png"))
        var info: [String: Any] = [
            "imageSize": [w, h], "faceCount": capture.faceCount, "yaw": capture.yaw, "roll": capture.roll,
            "eyes": [[capture.eyes.0.x, capture.eyes.0.y], [capture.eyes.1.x, capture.eyes.1.y]],
            "contourImage": capture.contour.map { [$0.x, $0.y] }, "hasPersonMask": capture.personMask != nil,
        ]
        if let data = try? JSONEncoder().encode(face.shape), let shape = try? JSONSerialization.jsonObject(with: data) { info["shape"] = shape }
        if let json = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: dir.appendingPathComponent("debug-shape.json"))
        }
    }
    #endif

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
        var withSides = meta
        withSides.sides = sides.isEmpty ? nil : sides.map(\.view)
        return GameCharacter(meta: withSides, texture: face.texture, sideTextures: sides.map(\.texture))
    }

    /// Adds a photo of the head turned halfway to one side. It is lined up with the head built
    /// from the front photo and worn on that side; a second photo of the same side replaces it.
    func addSide(_ image: UIImage, testPath: String? = nil) {
        guard let built, stage == .review else { return }
        sidesInFlight += 1
        sideMessage = nil
        let character = makeCharacter(built)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () -> (view: SideView, texture: UIImage) in
                let capture = try FaceAnalyzer.analyze(image, testPath: testPath)
                return try SideFit.build(capture: capture, shape: built.shape, head: HeadGeometryCache.output(for: character),
                                         frontTexture: built.texture.cgImage)
            }
            DispatchQueue.main.async {
                guard let self, self.built?.texture === built.texture else { return }   // retaken meanwhile
                self.sidesInFlight = max(0, self.sidesInFlight - 1)
                #if DEBUG
                switch result {
                case .success(let side): print("side photo: yaw \(side.view.yaw * 180 / .pi)°, side \(side.view.side), texture \(side.view.size)")
                case .failure(let error): print("side photo failed: \(error)")
                }
                #endif
                switch result {
                case .success(let side):
                    self.sides.removeAll { $0.view.side == side.view.side }
                    self.sides.append(side)
                    self.refreshPreview()
                case .failure(let error):
                    self.sideMessage = (error as? LocalizedError)?.errorDescription ?? "We couldn't use that photo. Try another."
                }
            }
        }
    }

    private func refreshPreview() {
        guard stage == .review, let built else { return }
        preview.show(makeCharacter(built), animated: false)
        debugTurn()
    }

    /// Debug: `-studioTurn 1.2` shows the new head from the side (simulator checks).
    private func debugTurn() {
        #if DEBUG
        if let turn = UserDefaults.standard.string(forKey: "studioTurn"), let angle = Float(turn) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.preview.turn(to: angle) }
        }
        #endif
    }

    func save(to store: CharacterStore) {
        guard let built else { return }
        var meta = makeCharacter(built).meta
        meta.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Mystery Guest" : name.trimmingCharacters(in: .whitespaces)
        meta.id = UUID()
        store.add(meta: meta, texture: built.texture, sideTextures: sides.map(\.texture))
    }

    func reset() {
        stage = .pick
        photo = nil
        landmarks = []
        built = nil
        sides = []
        sidesInFlight = 0
        sideMessage = nil
        pendingSides = []
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
    @State private var showSideCamera = false
    @State private var showScan = false
    @State private var sidePickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 16) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 20, height: 20) }
                        .buttonStyle(IconButtonStyle())
                        .accessibilityLabel("Close")
                    Spacer()
                    PartyTitle(text: "Face Studio", size: 26)
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
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "studioCamera") { showCamera = true }   // layout check
            if UserDefaults.standard.object(forKey: "studioScan") != nil { showScan = true }
            #endif
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    let depth = FaceDepth.read(from: data)   // Portrait-mode photos carry their depth
                    await MainActor.run { model.process(image, depth: depth) }
                }
                await MainActor.run { pickerItem = nil }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            GuidedCameraView { image, depth in model.process(image, depth: depth) }
        }
        .fullScreenCover(isPresented: $showScan) {
            FaceScanView { image, depth, sides in model.process(image, depth: depth, sides: sides) }
        }
        .fullScreenCover(isPresented: $showSideCamera) {
            GuidedCameraView(sideMode: true) { image, _ in model.addSide(image) }
        }
        .onChange(of: sidePickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await MainActor.run { model.addSide(image) }
                }
                await MainActor.run { sidePickerItem = nil }
            }
        }
    }

    // MARK: Pick

    private var pickView: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Theme.sky)
                    
                    .softShadow(0.6)
                    .frame(width: 210, height: 210)
                Image(systemName: "face.dashed").font(.system(size: 104, weight: .regular)).foregroundStyle(Theme.ink)
            }
            Text("Who's getting the big-head treatment?").font(.party(24)).multilineTextAlignment(.center).foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 8) {
                Label("Face the camera, eyes open", systemImage: "eye")
                Label("Good, even light — no heavy shadows", systemImage: "sun.max")
                Label("No sunglasses or hands on the face", systemImage: "eyeglasses")
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(16)
            .card(Theme.surface, cornerRadius: 18)
            Spacer()
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                // Front, left and right in one go: the scan takes the photos itself.
                Button { showScan = true } label: { Label("Scan My Face", systemImage: "faceid") }
                    .buttonStyle(CandyButtonStyle(color: Theme.coral))
                Button { showCamera = true } label: { Label("Take a Photo", systemImage: "camera.fill") }
                    .buttonStyle(CandyButtonStyle())
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose a Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(CandyButtonStyle())
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
                                        .stroke(Theme.butter, lineWidth: 2)
                                        .frame(width: model.faceBox.width * size.width, height: model.faceBox.height * size.height)
                                        .offset(x: model.faceBox.minX * size.width, y: model.faceBox.minY * size.height)
                                }
                                ForEach(Array(model.landmarks.enumerated()), id: \.offset) { _, p in
                                    Circle().fill(Theme.lime)
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
                            .foregroundStyle(step.done ? Theme.ink : Theme.ink.opacity(0.4))
                            .font(.title3.weight(.bold))
                            .symbolEffect(.pulse, isActive: !step.done)
                        Text(step.title).font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.ink).opacity(step.done ? 1 : 0.5)
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
                Theme.sky
                Circle().fill(Theme.surface.opacity(0.35)).frame(width: 240, height: 240).frame(maxHeight: .infinity)
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
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .card(Theme.sky, cornerRadius: 24)
            .padding(.horizontal)
            Text("Drag to spin them around").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink.opacity(0.65))

            ForEach(model.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(10)
                    .card(Theme.bubblegum, cornerRadius: 12)
                    .padding(.horizontal)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Who is this? (e.g. Uncle Ray)", text: $model.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .padding(14)
                        .card(Theme.surface, cornerRadius: 14)
                    sidePhotos
                    Text("Hat").font(.party(18)).foregroundStyle(Theme.ink)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(HatStyle.allCases) { h in
                                chip(h.label, symbol: h.symbol, selected: model.hat == h) { model.hat = h }
                            }
                        }
                    }
                    Text("Hair").font(.party(18)).foregroundStyle(Theme.ink)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(HairVolume.allCases) { h in
                                chip(h.label, symbol: nil, selected: model.hair == h) { model.hair = h }
                            }
                        }
                    }
                    Toggle(isOn: $model.googly) {
                        Label("Googly eyes", systemImage: "eyes").font(.party(18)).foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral)
                }
                .padding(.horizontal, 20)
            }
            HStack(spacing: 12) {
                Button("Retake") { model.reset() }
                    .buttonStyle(CandyButtonStyle(color: Theme.surface))
                    .frame(width: 130)
                Button("Add to cast") {
                    model.save(to: store)
                    dismiss()
                }
                .buttonStyle(CandyButtonStyle())
                .disabled(model.sideBusy)   // a side photo still lining up would be left out
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    /// Optional photos of each side of the head, so the cheeks, jaw and temples are real too.
    private var sidePhotos: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Side photos").font(.party(18)).foregroundStyle(Theme.ink)
            Text(model.sides.isEmpty ? "Optional. Add a photo with the head turned halfway to each side, and the sides of the head come from real photos too."
                 : (model.sides.count == 1 ? "One side added. Add the other side to finish." : "Both sides added."))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.7))
            HStack {
                chip("Take side photo", symbol: "camera.fill", selected: false) { showSideCamera = true }
                PhotosPicker(selection: $sidePickerItem, matching: .images) {
                    Label("Choose", systemImage: "photo")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .pill(Theme.surface)
                }
                if model.sideBusy { ProgressView() }
            }
            .disabled(model.sideBusy)
            if let message = model.sideMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(10)
                    .card(Theme.bubblegum, cornerRadius: 12)
            }
        }
    }

    private func expressionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                Text(title).font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .frame(width: 56, height: 44)
            .card(Theme.surface, cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
    }

    private func chip(_ title: String, symbol: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .pill(selected ? Theme.coral : Theme.surface)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
    }

    // MARK: Failed

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "face.dashed.fill").font(.system(size: 80)).foregroundStyle(Theme.ink)
                .frame(width: 140, height: 140)
                .card(Theme.bubblegum, cornerRadius: 70)
            Text("Hmm, that didn't work").font(.party(26)).foregroundStyle(Theme.ink)
            Text(message).font(.system(size: 16, weight: .semibold, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(Theme.ink.opacity(0.8))
            Spacer()
            Button("Try another photo") { model.reset() }.buttonStyle(CandyButtonStyle())
        }
        .padding(30)
    }
}
