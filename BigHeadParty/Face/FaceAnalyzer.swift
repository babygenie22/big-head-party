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
    /// All 76 landmarks normalized to the image (0...1, origin top-left) for the overlay UI.
    let overlayPoints: [CGPoint]
    /// Normalized face box (origin top-left) for the overlay UI.
    let overlayBox: CGRect
    /// Person/background mask (white = person), if segmentation succeeded.
    let personMask: CVPixelBuffer?
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
        let overlay: [CGPoint]
    }

    /// Runs Apple's Vision face-landmark model (76 points) plus person segmentation, on device.
    /// If the landmarks come back unusable, tries the previous model revision, then falls back to
    /// typical human proportions inside the detected face box (`estimated` is then true).
    static func analyze(_ uiImage: UIImage) throws -> FaceCapture {
        guard let cg = uiImage.normalizedCGImage(maxDimension: 1600) else { throw FaceAnalyzerError.unreadableImage }
        let size = CGSize(width: cg.width, height: cg.height)
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])

        var bestFace: VNFaceObservation?
        var faceCount = 0
        var features: Features?
        for revision in [VNDetectFaceLandmarksRequestRevision3, VNDetectFaceLandmarksRequestRevision2] {
            let request = VNDetectFaceLandmarksRequest()
            request.revision = revision
            #if targetEnvironment(simulator)
            request.usesCPUOnly = true
            #endif
            guard (try? handler.perform([request])) != nil, let faces = request.results, !faces.isEmpty else { continue }
            // The biggest face wins (group photos: the person closest to the camera).
            let face = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }!
            if bestFace == nil { bestFace = face; faceCount = faces.count }
            if let f = landmarkFeatures(face, size: size) {
                bestFace = face
                faceCount = faces.count
                features = f
                break
            }
        }
        guard let face = bestFace else { throw FaceAnalyzerError.noFace }
        let estimated = features == nil
        let f = features ?? estimatedFeatures(face, size: size)

        let bb = face.boundingBox
        let overlayBox = CGRect(x: bb.minX, y: 1 - bb.maxY, width: bb.width, height: bb.height)

        // Person segmentation lets us drop the photo's background and keep hair.
        var mask: CVPixelBuffer?
        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = .accurate
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        if (try? handler.perform([segmentation])) != nil {
            mask = segmentation.results?.first?.pixelBuffer
        }

        return FaceCapture(image: cg,
                           eyes: f.eyes,
                           nose: f.nose,
                           outerLips: f.lips,
                           contour: f.contour,
                           overlayPoints: f.overlay,
                           overlayBox: overlayBox,
                           personMask: mask,
                           yaw: face.yaw?.doubleValue ?? 0,
                           roll: face.roll?.doubleValue ?? 0,
                           faceCount: faceCount,
                           estimated: estimated)
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
        return Features(eyes: eyes, nose: nose, lips: lips, contour: contour, overlay: overlay)
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
        return Features(eyes: eyes, nose: nose, lips: lips, contour: contour, overlay: overlay)
    }
}

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
