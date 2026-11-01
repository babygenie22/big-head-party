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

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "guided-camera")
    private var frame = 0
    private var usingFront = true   // queue-side copy of `front`
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var onPhoto: ((UIImage) -> Void)?

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

    func capture(_ done: @escaping (UIImage) -> Void) {
        onPhoto = done
        queue.async {
            // Upright for however the phone is held right now (set at capture time: an angle set
            // once at setup didn't stick, and photos came out sideways).
            if let c = self.photoOutput.connection(with: .video) {
                let angle = self.rotation?.videoRotationAngleForHorizonLevelCapture ?? 90
                if c.isVideoRotationAngleSupported(angle) { c.videoRotationAngle = angle }
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configure(front: Bool = true) {
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach(session.removeInput)
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back),
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
        guard frame % 4 == 0, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request])
        let faces = request.results ?? []
        let face = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
        let box = face.map { CGRect(x: $0.boundingBox.minX, y: 1 - $0.boundingBox.maxY, width: $0.boundingBox.width, height: $0.boundingBox.height) }
        let light = box.map { brightness(pixels, in: $0) }
        let next = Self.coach(box: box, yaw: face?.yaw?.doubleValue ?? 0, roll: face?.roll?.doubleValue ?? 0,
                              pitch: face?.pitch?.doubleValue ?? 0, brightness: light ?? 0.5, faces: faces.count, selfie: usingFront)
        DispatchQueue.main.async {
            guard next != self.hint else { return }
            if next.ready && !self.hint.ready { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            withAnimation(.easeOut(duration: 0.2)) { self.hint = next }
        }
    }

    /// The single most useful thing to fix next. `box` is normalized, top-left origin, as shown.
    static func coach(box: CGRect?, yaw: Double, roll: Double, pitch: Double, brightness: Double, faces: Int, selfie: Bool) -> Hint {
        guard let box else { return Hint(text: selfie ? "Put your face in the oval" : "Point the camera at their face", symbol: "face.dashed") }
        // Vision's face box covers brows to chin; in the oval that's about half its width.
        if box.width < 0.36 { return Hint(text: selfie ? "Move closer" : "Get closer", symbol: "plus.magnifyingglass") }
        if box.width > 0.66 { return Hint(text: selfie ? "Back up a little" : "Step back a little", symbol: "minus.magnifyingglass") }
        let dx = box.midX - oval.midX, dy = box.midY - (oval.minY + oval.height * 0.55)
        if abs(dx) > 0.09 || abs(dy) > 0.09 {
            return Hint(text: selfie ? "Center your face in the oval" : "Center their face in the oval", symbol: "viewfinder")
        }
        // Positive yaw: the nose points to the right of the picture.
        if abs(yaw) > 0.3 {
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
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async {
            self.onPhoto?(image)
            self.onPhoto = nil
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
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
    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = GuidedCamera()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title) }
                    Spacer()
                    Button { camera.flip() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera.fill").font(.title) }
                        .accessibilityLabel(camera.front ? "Switch to the back camera" : "Switch to the selfie camera")
                }
                .foregroundStyle(.white)
                .padding(.horizontal)

                hintBanner

                GeometryReader { geo in
                    let o = GuidedCamera.oval
                    ZStack(alignment: .topLeading) {
                        CameraPreview(session: camera.session)
                        Ellipse()
                            .stroke(camera.hint.ready ? Theme.teal : .white.opacity(0.85),
                                    style: StrokeStyle(lineWidth: camera.hint.ready ? 6 : 3, dash: camera.hint.ready ? [] : [10, 8]))
                            .frame(width: o.width * geo.size.width, height: o.height * geo.size.height)
                            .offset(x: o.minX * geo.size.width, y: o.minY * geo.size.height)
                            .shadow(color: camera.hint.ready ? Theme.teal.opacity(0.8) : .clear, radius: 12)
                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 10)

                Spacer(minLength: 0)
                Button {
                    camera.capture { image in
                        onPhoto(image)
                        dismiss()
                    }
                } label: {
                    ZStack {
                        Circle().fill(camera.hint.ready ? Theme.teal : .white).frame(width: 74, height: 74)
                        Circle().stroke(.white, lineWidth: 4).frame(width: 88, height: 88)
                    }
                }
                .accessibilityLabel("Take photo")
                .padding(.bottom, 20)
            }
            .padding(.top, 8)

            if camera.denied {
                VStack(spacing: 14) {
                    Text("Camera access is off").font(.party(24))
                    Text("Allow camera access for Big Head Party in Settings, or choose a photo instead.")
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(ChunkyButtonStyle())
                }
                .foregroundStyle(.white)
                .padding(30)
                .background(Theme.deep, in: RoundedRectangle(cornerRadius: 24))
                .padding()
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var hintBanner: some View {
        Label(camera.hint.text, systemImage: camera.hint.symbol)
            .font(.headline)
            .foregroundStyle(camera.hint.ready ? .black : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(camera.hint.ready ? Theme.teal : Color.white.opacity(0.15), in: Capsule())
            .id(camera.hint.text)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
