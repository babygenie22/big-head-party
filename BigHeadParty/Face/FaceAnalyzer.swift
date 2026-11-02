import UIKit
import Vision

/// What the on-device AI found in a photo.
struct FaceCapture {
    /// The photo, upright and downscaled.
    let image: CGImage
    /// Eye centers in Vision image coordinates (pixels, origin bottom-left), sorted left→right.
    let eyes: (CGPoint, CGPoint)
    /// Landmark regions in Vision image coordinates.
    let nose: [CGPoint]
    let outerLips: [CGPoint]
    let contour: [CGPoint]
    /// Both eyebrows and both eye outlines, used to place the brow ridge and size the eye sockets.
    let eyebrows: [[CGPoint]]
    let eyeOutlines: [[CGPoint]]
    /// All 76 landmarks normalized to the image (0...1, origin top-left) for the overlay UI.
    let overlayPoints: [CGPoint]
    /// Normalized face box (origin top-left) for the overlay UI.
    let overlayBox: CGRect
    /// Person/background mask (white = person), if segmentation succeeded.
    let personMask: CVPixelBuffer?
    /// Measured depth lined up with `image`, when the photo had it (TrueDepth or Portrait mode).
    var depth: FaceDepth? = nil
    let yaw: Double
    let roll: Double
    let faceCount: Int
    /// True when the features were estimated from the face box instead of measured.
    var estimated = false
}

enum FaceAnalyzerError: LocalizedError {
    case unreadableImage
    case noFace
    case missingLandmarks

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "We couldn't read that image. Try another photo."
        case .noFace: return "No face found. Try a well-lit photo where the face looks at the camera."
        case .missingLandmarks: return "We found a face but couldn't map its features. Try a sharper, front-facing photo."
        }
    }
}

enum FaceAnalyzer {
    private struct Features {
        let eyes: (CGPoint, CGPoint)
        let nose: [CGPoint]
        let lips: [CGPoint]
        let contour: [CGPoint]
        let eyebrows: [[CGPoint]]
        let eyeOutlines: [[CGPoint]]
        let overlay: [CGPoint]
    }

    /// Runs Apple's Vision face-landmark model (76 points) plus person segmentation, on device.
    /// If the landmarks come back unusable, tries the previous model revision, then falls back to
    /// typical human proportions inside the detected face box (`estimated` is then true).
    static func analyze(_ uiImage: UIImage, depth: FaceDepth? = nil) throws -> FaceCapture {
        // Big enough that a face filling only part of a phone photo still has the pixels for a
        // 2048² texture; 1600 px left typical faces upscaled and soft.
        guard var cg = uiImage.normalizedCGImage(maxDimension: 3200) else { throw FaceAnalyzerError.unreadableImage }
        #if targetEnvironment(simulator)
        if var canned = cannedCapture(cg) { canned.depth = depth; return canned }
        #endif

        guard var found = biggestFace(in: cg) else { throw FaceAnalyzerError.noFace }
        var depth = depth
        // A sideways or upside-down photo: turn it upright and look again. Left as it was, the eyes
        // sort into the wrong order and the face gets "straightened" onto the head upside down.
        if let roll = found.face.roll?.doubleValue, abs(roll) > .pi / 4 {
            let quarter = Int((roll / (.pi / 2)).rounded())
            for turns in [quarter, -quarter] {
                guard let turned = cg.rotated(quarterTurns: turns), let upright = biggestFace(in: turned),
                      abs(upright.face.roll?.doubleValue ?? 0) < .pi / 4 else { continue }
                cg = turned
                found = upright
                depth = nil   // the depth map no longer lines up with the turned photo
                break
            }
        }
        let face = found.face
        let size = CGSize(width: cg.width, height: cg.height)
        let estimated = found.features == nil
        let f = found.features ?? estimatedFeatures(face, size: size)

        let bb = face.boundingBox
        let overlayBox = CGRect(x: bb.minX, y: 1 - bb.maxY, width: bb.width, height: bb.height)

        // Person segmentation lets us drop the photo's background and keep hair.
        var mask: CVPixelBuffer?
        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = .accurate
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        if (try? VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:]).perform([segmentation])) != nil {
            mask = segmentation.results?.first?.pixelBuffer
        }

        return FaceCapture(image: cg,
                           eyes: f.eyes,
                           nose: f.nose,
                           outerLips: f.lips,
                           contour: f.contour,
                           eyebrows: f.eyebrows,
                           eyeOutlines: f.eyeOutlines,
                           overlayPoints: f.overlay,
                           overlayBox: overlayBox,
                           personMask: mask,
                           depth: depth,
                           yaw: face.yaw?.doubleValue ?? 0,
                           roll: face.roll?.doubleValue ?? 0,
                           faceCount: found.count,
                           estimated: estimated)
    }

    /// The biggest face (group photos: the person closest to the camera), how many there are, and
    /// its landmarks: from Vision's current model, or the previous one if those came back unusable.
    private static func biggestFace(in cg: CGImage) -> (face: VNFaceObservation, count: Int, features: Features?)? {
        let size = CGSize(width: cg.width, height: cg.height)
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        var best: (face: VNFaceObservation, count: Int, features: Features?)?
        for revision in [VNDetectFaceLandmarksRequestRevision3, VNDetectFaceLandmarksRequestRevision2] {
            let request = VNDetectFaceLandmarksRequest()
            request.revision = revision
            #if targetEnvironment(simulator)
            request.usesCPUOnly = true
            #endif
            guard (try? handler.perform([request])) != nil, let faces = request.results, !faces.isEmpty else { continue }
            let face = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }!
            if best == nil { best = (face, faces.count, nil) }
            if let f = landmarkFeatures(face, size: size) { return (face, faces.count, f) }
        }
        return best
    }

    /// Landmarks from Vision, or nil if they're missing or collapsed.
    private static func landmarkFeatures(_ face: VNFaceObservation, size: CGSize) -> Features? {
        guard let lm = face.landmarks else { return nil }
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] { region?.pointsInImage(imageSize: size) ?? [] }
        func centroid(_ pts: [CGPoint]) -> CGPoint? {
            guard !pts.isEmpty else { return nil }
            let s = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: s.x / CGFloat(pts.count), y: s.y / CGFloat(pts.count))
        }
        let pupilA = centroid(points(lm.leftPupil)) ?? centroid(points(lm.leftEye))
        let pupilB = centroid(points(lm.rightPupil)) ?? centroid(points(lm.rightEye))
        let nose = points(lm.nose), lips = points(lm.outerLips), contour = points(lm.faceContour)
        guard let ea = pupilA, let eb = pupilB, !nose.isEmpty, !lips.isEmpty, contour.count >= 5 else { return nil }
        let eyes = ea.x < eb.x ? (ea, eb) : (eb, ea)
        // Real eyes sit roughly a third of the face width apart; far less means the points collapsed.
        let faceWidth = face.boundingBox.width * size.width
        guard hypot(eyes.1.x - eyes.0.x, eyes.1.y - eyes.0.y) > faceWidth * 0.18 else { return nil }
        let overlay = points(lm.allPoints).map { CGPoint(x: $0.x / size.width, y: 1 - $0.y / size.height) }
        return Features(eyes: eyes, nose: nose, lips: lips, contour: contour,
                        eyebrows: [points(lm.leftEyebrow), points(lm.rightEyebrow)].filter { !$0.isEmpty },
                        eyeOutlines: [points(lm.leftEye), points(lm.rightEye)].filter { $0.count >= 4 },
                        overlay: overlay)
    }

    /// Typical proportions inside Vision's face box (box-relative, origin bottom-left).
    private static func estimatedFeatures(_ face: VNFaceObservation, size: CGSize) -> Features {
        let bb = face.boundingBox
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (bb.minX + x * bb.width) * size.width, y: (bb.minY + y * bb.height) * size.height)
        }
        let eyes = (p(0.3, 0.62), p(0.7, 0.62))
        let nose = [p(0.42, 0.36), p(0.5, 0.33), p(0.58, 0.36)]
        let lips = [p(0.34, 0.2), p(0.5, 0.25), p(0.66, 0.2), p(0.5, 0.14)]
        let contour = (0...16).map { i -> CGPoint in
            let t = CGFloat(i) / 16 * .pi
            return p(0.5 - 0.48 * cos(t) * (1 - 0.15 * sin(t)), 0.6 - 0.6 * pow(sin(t), 0.8))
        }
        let all = [eyes.0, eyes.1] + nose + lips + contour
        let overlay = all.map { CGPoint(x: $0.x / size.width, y: 1 - $0.y / size.height) }
        return Features(eyes: eyes, nose: nose, lips: lips, contour: contour, eyebrows: [], eyeOutlines: [], overlay: overlay)
    }
}

extension CGImage {
    /// Rotated by quarter turns (positive = counter-clockwise).
    func rotated(quarterTurns: Int) -> CGImage? {
        let k = ((quarterTurns % 4) + 4) % 4
        guard k != 0 else { return self }
        let w = CGFloat(width), h = CGFloat(height)
        let (nw, nh) = k % 2 == 1 ? (height, width) : (width, height)
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.translateBy(x: CGFloat(nw) / 2, y: CGFloat(nh) / 2)
        ctx.rotate(by: CGFloat(k) * .pi / 2)
        ctx.draw(self, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        return ctx.makeImage()
    }
}

#if targetEnvironment(simulator)
/// Vision's landmark model gives garbage on the simulator's CPU, so debug runs of
/// `-studioTestImage photo.jpg` read landmarks computed on a Mac from `photo.jpg.lm.json`
/// (and `photo.jpg.mask.png`), written by a small macOS Vision script.
private func cannedCapture(_ cg: CGImage) -> FaceCapture? {
    guard let path = UserDefaults.standard.string(forKey: "studioTestImage"),
          let data = FileManager.default.contents(atPath: path + ".lm.json"),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    func pts(_ key: String) -> [CGPoint] { ((json[key] as? [[Double]]) ?? []).map { CGPoint(x: $0[0], y: $0[1]) } }
    func centroid(_ p: [CGPoint]) -> CGPoint { CGPoint(x: p.map(\.x).reduce(0, +) / CGFloat(p.count), y: p.map(\.y).reduce(0, +) / CGFloat(p.count)) }
    let a = centroid(pts("leftPupil")), b = centroid(pts("rightPupil"))
    let w = CGFloat(cg.width), h = CGFloat(cg.height)
    let box = (json["box"] as? [Double]) ?? [0, 0, 1, 1]
    var mask: CVPixelBuffer?
    if let m = UIImage(contentsOfFile: path + ".mask.png")?.cgImage {
        CVPixelBufferCreate(nil, m.width, m.height, kCVPixelFormatType_OneComponent8, nil, &mask)
        if let mask {
            CVPixelBufferLockBaseAddress(mask, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(mask), width: m.width, height: m.height, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(mask), space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)
            ctx?.draw(m, in: CGRect(x: 0, y: 0, width: m.width, height: m.height))
            CVPixelBufferUnlockBaseAddress(mask, [])
        }
    }
    return FaceCapture(image: cg, eyes: a.x < b.x ? (a, b) : (b, a), nose: pts("nose"), outerLips: pts("outerLips"),
                       contour: pts("faceContour"), eyebrows: [pts("leftEyebrow"), pts("rightEyebrow")],
                       eyeOutlines: [pts("leftEye"), pts("rightEye")],
                       overlayPoints: pts("allPoints").map { CGPoint(x: $0.x / w, y: 1 - $0.y / h) },
                       overlayBox: CGRect(x: box[0], y: 1 - box[1] - box[3], width: box[2], height: box[3]),
                       personMask: mask, yaw: json["yaw"] as? Double ?? 0, roll: json["roll"] as? Double ?? 0,
                       faceCount: json["faceCount"] as? Int ?? 1)
}
#endif

extension UIImage {
    /// Redraws the image upright (applying EXIF orientation) and caps its size.
    func normalizedCGImage(maxDimension: CGFloat) -> CGImage? {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            self.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.cgImage
    }
}
