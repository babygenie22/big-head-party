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
    /// Runs Apple's Vision face-landmark model (76 points) plus person segmentation.
    /// Everything stays on device.
    static func analyze(_ uiImage: UIImage) throws -> FaceCapture {
        guard let cg = uiImage.normalizedCGImage(maxDimension: 1600) else { throw FaceAnalyzerError.unreadableImage }
        let size = CGSize(width: cg.width, height: cg.height)

        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.revision = VNDetectFaceLandmarksRequestRevision3
        #if targetEnvironment(simulator)
        // The Simulator's default Vision path returns collapsed landmarks; the CPU path is correct.
        landmarksRequest.usesCPUOnly = true
        #endif
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        try handler.perform([landmarksRequest])

        guard let faces = landmarksRequest.results, !faces.isEmpty else { throw FaceAnalyzerError.noFace }
        // The biggest face wins (group photos: the person closest to the camera).
        let face = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }!
        guard let lm = face.landmarks else { throw FaceAnalyzerError.missingLandmarks }

        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            region?.pointsInImage(imageSize: size) ?? []
        }
        func centroid(_ pts: [CGPoint]) -> CGPoint? {
            guard !pts.isEmpty else { return nil }
            let s = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: s.x / CGFloat(pts.count), y: s.y / CGFloat(pts.count))
        }

        let pupilA = centroid(points(lm.leftPupil)) ?? centroid(points(lm.leftEye))
        let pupilB = centroid(points(lm.rightPupil)) ?? centroid(points(lm.rightEye))
        let nose = points(lm.nose)
        let lips = points(lm.outerLips)
        let contour = points(lm.faceContour)
        guard let ea = pupilA, let eb = pupilB, !nose.isEmpty, !lips.isEmpty, contour.count >= 5 else {
            throw FaceAnalyzerError.missingLandmarks
        }
        let eyes = ea.x < eb.x ? (ea, eb) : (eb, ea)
        // Real eyes sit roughly a third of the face width apart. Anything far smaller means the
        // landmarks collapsed; better to ask for another photo than to sculpt a broken head.
        let faceWidth = face.boundingBox.width * size.width
        guard hypot(eyes.1.x - eyes.0.x, eyes.1.y - eyes.0.y) > faceWidth * 0.18 else {
            throw FaceAnalyzerError.missingLandmarks
        }

        let overlay = points(lm.allPoints).map { CGPoint(x: $0.x / size.width, y: 1 - $0.y / size.height) }
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
                           eyes: eyes,
                           nose: nose,
                           outerLips: lips,
                           contour: contour,
                           overlayPoints: overlay,
                           overlayBox: overlayBox,
                           personMask: mask,
                           yaw: face.yaw?.doubleValue ?? 0,
                           roll: face.roll?.doubleValue ?? 0,
                           faceCount: faces.count)
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
