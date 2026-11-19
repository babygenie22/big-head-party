import SwiftUI
import AVFoundation
import Vision

/// A camera that coaches the shot: it watches the live picture with Vision and tells people to
/// move closer, center up, turn, level their head or find light, and lights the oval green
/// when the photo will make a great big head.
final class GuidedCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    struct Hint: Equatable {
        let text: String
        let symbol: String
        var ready = false
    }

    @Published private(set) var hint = Hint(text: "Put your face in the oval", symbol: "face.dashed")
    @Published private(set) var front = true
    @Published private(set) var denied = false
    /// Coaching for a side photo (head turned halfway) instead of a front one.
    var sideMode = false

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "guided-camera")
    private var frame = 0
    private var usingFront = true   // queue-side copy of `front`
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var onPhoto: ((UIImage?, FaceDepth?) -> Void)?

    // Face scan (main thread only): the front photo and both sides in one go, taken by the
    // camera itself as each pose is reached.
    private var tracker: FaceScan?
    @Published private(set) var scanStep: FaceScan.Step = .front
    /// Which way the first side photo was turned (+1: toward the right of the picture).
    @Published private(set) var scanTurn = 0.0
    /// How long the face has been held in place for the front photo (0…1), and how far the
    /// head is turned toward a side (−1…1).
    @Published private(set) var scanHold = 0.0
    @Published private(set) var scanTurnNow = 0.0
    /// Small copies of the photos taken so far, for the screen.
    @Published private(set) var scanThumbs: [UIImage] = []
    private var scanning = false   // set before the camera starts, read on the camera queue
    private(set) var scanFront: (image: UIImage, depth: FaceDepth?)?
    private(set) var scanSides: [UIImage] = []

    /// Call before `start()`: this camera runs the three-photo scan instead of one guided photo.
    func beginScan() {
        tracker = FaceScan()
        scanning = true
        hint = Hint(text: "Put your face in the circle", symbol: "face.dashed")
    }

    #if DEBUG
    /// Simulator layout check (no camera there): show the scan as if `step` photos were taken.
    func debugScan(step: Int) {
        guard step > 0 else { return }
        scanTurn = 1
        scanStep = FaceScan.Step(rawValue: min(step, 2)) ?? .front
        scanTurnNow = step == 1 ? -0.6 : 0
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        scanThumbs = Array(repeating: blank, count: min(step, 2))
    }
    #endif

    private func takeScanPhoto() {
        // Side photos are taken while the head is moving: less processing, less shutter lag.
        shoot(fast: tracker?.step != .front) { [weak self] image, depth in
            guard let self, var scan = self.tracker else { return }
            if let image {
                if self.scanFront == nil { self.scanFront = (image, depth) } else { self.scanSides.append(image) }
                self.scanThumbs.append(image.preparingThumbnail(of: CGSize(width: 240, height: 320)) ?? image)
                scan.shot()
            } else {
                scan.missed()
            }
            self.tracker = scan
            self.scanTurn = scan.firstTurn
            self.scanHold = scan.hold
            self.scanStep = scan.step
        }
    }

    /// Where the oval sits in the 3:4 picture (normalized, top-left origin).
    static let oval = CGRect(x: 0.2, y: 0.17, width: 0.6, height: 0.62)

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: queue.async { self.configure() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                if ok { self.queue.async { self.configure() } } else { DispatchQueue.main.async { self.denied = true } }
            }
        default: denied = true
        }
    }

    func stop() { queue.async { self.session.stopRunning() } }

    func flip() {
        queue.async {
            let wantFront = !self.front
            self.configure(front: wantFront)
            DispatchQueue.main.async { self.front = wantFront }
        }
    }

    /// The photo, plus the face's measured depth when the TrueDepth camera took it.
    func capture(_ done: @escaping (UIImage, FaceDepth?) -> Void) {
        shoot { image, depth in
            if let image { done(image, depth) }
        }
    }

    /// Takes a photo; `done` gets nil when the camera couldn't deliver one.
    private func shoot(fast: Bool = false, _ done: @escaping (UIImage?, FaceDepth?) -> Void) {
        onPhoto = done
        queue.async {
            // No camera (access denied, or still starting): asking for a photo would crash.
            guard self.session.isRunning, self.photoOutput.connection(with: .video)?.isActive == true else {
                DispatchQueue.main.async {
                    let done = self.onPhoto
                    self.onPhoto = nil
                    done?(nil, nil)
                }
                return
            }
            // Upright for however the phone is held right now (set at capture time: an angle set
            // once at setup didn't stick, and photos came out sideways).
            if let c = self.photoOutput.connection(with: .video) {
                let angle = self.rotation?.videoRotationAngleForHorizonLevelCapture ?? 90
                if c.isVideoRotationAngleSupported(angle) { c.videoRotationAngle = angle }
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = fast ? .balanced : .quality
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            settings.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliveryEnabled
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configure(front: Bool = true) {
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach(session.removeInput)
        // The TrueDepth selfie camera (Face ID phones) also measures the face's shape.
        let trueDepth = front ? AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) : nil
        guard let device = trueDepth ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
        }
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        // Every pixel the camera has: the photo becomes the head's skin, so resolution is detail.
        if let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            photoOutput.maxPhotoDimensions = largest
        }
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        usingFront = front
        // Upright frames, mirrored like the preview for the selfie camera, so Vision's numbers
        // match what people see on screen.
        if let c = videoOutput.connection(with: .video) {
            if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = front }
        }
        if let c = photoOutput.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
    }

    // MARK: Live coaching

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frame += 1
        // The scan follows the head as it turns, so it looks twice as often.
        guard frame % (scanning ? 2 : 4) == 0, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request])
        let faces = request.results ?? []
        let face = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
        let box = face.map { CGRect(x: $0.boundingBox.minX, y: 1 - $0.boundingBox.maxY, width: $0.boundingBox.width, height: $0.boundingBox.height) }
        let light = box.map { brightness(pixels, in: $0) }
        let next = Self.coach(box: box, yaw: face?.yaw?.doubleValue ?? 0, roll: face?.roll?.doubleValue ?? 0,
                              pitch: face?.pitch?.doubleValue ?? 0, brightness: light ?? 0.5, faces: faces.count, selfie: usingFront, side: sideMode)
        let reading = FaceScan.Reading(box: box, yaw: face?.yaw?.doubleValue ?? 0, roll: face?.roll?.doubleValue ?? 0, brightness: light ?? 0.5)
        DispatchQueue.main.async {
            var next = next
            if var scan = self.tracker {
                let (hint, shoot) = scan.look(reading, now: CACurrentMediaTime())
                self.tracker = scan
                let hold = (scan.hold * 20).rounded() / 20
                if hold != self.scanHold { self.scanHold = hold }
                let turn = (scan.turn * 20).rounded() / 20
                if turn != self.scanTurnNow { self.scanTurnNow = turn }
                next = hint
                if shoot { self.takeScanPhoto() }
            }
            guard next != self.hint else { return }
            if next.ready && !self.hint.ready { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            withAnimation(.easeOut(duration: 0.2)) { self.hint = next }
        }
    }

    /// The single most useful thing to fix next. `box` is normalized, top-left origin, as shown.
    static func coach(box: CGRect?, yaw: Double, roll: Double, pitch: Double, brightness: Double, faces: Int, selfie: Bool, side: Bool = false) -> Hint {
        guard let box else { return Hint(text: selfie ? "Put your face in the oval" : "Point the camera at their face", symbol: "face.dashed") }
        // Vision's face box covers brows to chin; in the oval that's about half its width.
        if box.width < 0.36 { return Hint(text: selfie ? "Move closer" : "Get closer", symbol: "plus.magnifyingglass") }
        if box.width > 0.66 { return Hint(text: selfie ? "Back up a little" : "Step back a little", symbol: "minus.magnifyingglass") }
        let dx = box.midX - oval.midX, dy = box.midY - (oval.minY + oval.height * 0.55)
        if abs(dx) > 0.09 || abs(dy) > 0.09 {
            return Hint(text: selfie ? "Center your face in the oval" : "Center their face in the oval", symbol: "viewfinder")
        }
        if side {
            // A side photo wants the head turned about halfway: far enough to show the cheek and
            // jaw side-on, not so far that the far eye disappears and the face can't be lined up.
            if abs(yaw) < 0.45 { return Hint(text: selfie ? "Turn your head halfway to one side" : "Ask them to turn halfway to one side", symbol: "arrow.left.and.right") }
            if abs(yaw) > 1.1 { return Hint(text: "Not so far — keep both eyes in view", symbol: "eye") }
        } else if abs(yaw) > 0.3 {
            // Positive yaw: the nose points to the right of the picture.
            let left = yaw > 0
            if selfie { return Hint(text: "Turn a little to your \(left ? "left" : "right")", symbol: left ? "arrow.left" : "arrow.right") }
            return Hint(text: "Ask them to face the camera", symbol: "arrow.left.and.right")
        }
        if abs(roll) > 0.25 { return Hint(text: selfie ? "Keep your head level" : "Hold the phone level", symbol: "level") }
        if pitch > 0.45 { return Hint(text: "Lift your chin a little", symbol: "arrow.up") }
        if pitch < -0.45 { return Hint(text: "Lower your chin a little", symbol: "arrow.down") }
        if brightness < 0.25 { return Hint(text: "Too dark — face a window or a lamp", symbol: "sun.max") }
        if brightness > 0.88 { return Hint(text: "Too bright — step out of direct light", symbol: "sun.max.trianglebadge.exclamationmark") }
        if faces > 1 { return Hint(text: "Perfect! (Only the biggest face is used)", symbol: "checkmark.circle.fill", ready: true) }
        return Hint(text: "Perfect — hold still and snap!", symbol: "checkmark.circle.fill", ready: true)
    }

    /// Mean luma (0...1) inside the face box, from a sparse grid of the Y plane.
    private func brightness(_ pixels: CVPixelBuffer, in box: CGRect) -> Double {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return 0.5 }
        let w = CVPixelBufferGetWidthOfPlane(pixels, 0), h = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let y = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, n = 0
        for j in stride(from: Int(box.minY * CGFloat(h)), to: Int(box.maxY * CGFloat(h)), by: 8) where j >= 0 && j < h {
            for i in stride(from: Int(box.minX * CGFloat(w)), to: Int(box.maxX * CGFloat(w)), by: 8) where i >= 0 && i < w {
                sum += Int(y[j * row + i]); n += 1
            }
        }
        return n > 0 ? Double(sum) / Double(n) / 255 : 0.5
    }

    // MARK: Photo

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        let image = data.flatMap { UIImage(data: $0) }
        // The depth map is stored in the file beside the picture, turned the same way.
        let depth = image == nil ? nil : data.flatMap { FaceDepth.read(from: $0) }
        DispatchQueue.main.async {
            let done = self.onPhoto
            self.onPhoto = nil
            done?(image, depth)
        }
    }
}

/// Shown over a camera screen when the app isn't allowed to use the camera.
struct CameraDeniedCard: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("Camera access is off").font(.party(24))
                .foregroundStyle(Theme.ink)
            Text("Allow camera access for Big Head Party in Settings, or choose a photo instead.")
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(CandyButtonStyle())
        }
        .foregroundStyle(Theme.ink)
        .padding(30)
        .card(Theme.surface, cornerRadius: 24)
        .padding()
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspect   // exactly the 3:4 photo, so the oval means what it says
        if let c = view.preview.connection, c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

struct GuidedCameraView: View {
    var sideMode = false
    let onPhoto: (UIImage, FaceDepth?) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = GuidedCamera()

    var body: some View {
        ZStack {
            // Kept dark on purpose: a bright yellow screen would tint the selfie.
            Theme.deep.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 20, height: 20) }
                        .buttonStyle(IconButtonStyle())
                        .accessibilityLabel("Close")
                    Spacer()
                    Button { camera.flip() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera.fill").frame(width: 24, height: 20) }
                        .buttonStyle(IconButtonStyle())
                        .accessibilityLabel(camera.front ? "Switch to the back camera" : "Switch to the selfie camera")
                }
                .padding(.horizontal)

                hintBanner

                GeometryReader { geo in
                    let o = GuidedCamera.oval
                    ZStack(alignment: .topLeading) {
                        CameraPreview(session: camera.session)
                        Ellipse()
                            .stroke(camera.hint.ready ? Theme.lime : Theme.butter,
                                    style: StrokeStyle(lineWidth: camera.hint.ready ? 6 : 3, dash: camera.hint.ready ? [] : [10, 8]))
                            .frame(width: o.width * geo.size.width, height: o.height * geo.size.height)
                            .offset(x: o.minX * geo.size.width, y: o.minY * geo.size.height)

                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(camera.hint.ready ? Theme.lime : Theme.surface.opacity(0.6), lineWidth: 3))
                .padding(.horizontal, 10)

                Spacer(minLength: 0)
                Button {
                    camera.capture { image, depth in
                        onPhoto(image, depth)
                        dismiss()
                    }
                } label: {
                    ZStack {
                        Circle().fill(Theme.ink).frame(width: 84, height: 84).offset(x: 5, y: 5)
                        Circle().fill(camera.hint.ready ? Theme.lime : Theme.surface)
                            
                            .frame(width: 84, height: 84)
                        Image(systemName: "camera.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.ink)
                    }
                }
                .accessibilityLabel("Take photo")
                .padding(.bottom, 20)
            }
            .padding(.top, 8)

            if camera.denied { CameraDeniedCard() }
        }
        .onAppear {
            camera.sideMode = sideMode
            camera.start()
        }
        .onDisappear { camera.stop() }
    }

    private var hintBanner: some View {
        Label(camera.hint.text, systemImage: camera.hint.symbol)
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .pill(camera.hint.ready ? Theme.lime : Theme.surface)
            .id(camera.hint.text)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
