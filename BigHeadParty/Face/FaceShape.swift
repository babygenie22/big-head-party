import CoreGraphics
import simd

/// The geometry of one face, expressed in *texture space*.
///
/// Texture space is the shared coordinate system between the face texture (a 1024×1024 image)
/// and the 3D head mesh: `u` runs left→right, `v` runs top→bottom, both in 0...1.
/// Every face — whether it came from a photo or was painted for a default character — is
/// aligned so that the two eyes land on `FaceLayout.leftEye` / `FaceLayout.rightEye`.
/// The remaining features (nose, mouth, chin, jawline) keep the person's real proportions,
/// and the head sculptor bends the 3D mesh to match them. That is what makes the head look
/// like *them* rather than a generic mannequin wearing their photo.
struct FaceShape: Codable, Equatable {
    var leftEye: CGPoint      // viewer's left (smaller u)
    var rightEye: CGPoint
    var noseTip: CGPoint
    var mouthCenter: CGPoint
    var mouthWidth: CGFloat
    var chin: CGPoint
    /// Jawline from ear to ear through the chin (Vision's faceContour, 7–17 points).
    var contour: [CGPoint]

    var eyeLineV: CGFloat { (leftEye.y + rightEye.y) / 2 }
    var midlineU: CGFloat { (leftEye.x + rightEye.x) / 2 }
}

enum FaceLayout {
    /// Texture resolution for generated faces.
    static let textureSize: CGFloat = 1024
    /// Canonical eye positions. Every face texture is rotated/scaled so the eyes land here.
    static let leftEye = CGPoint(x: 0.36, y: 0.40)
    static let rightEye = CGPoint(x: 0.64, y: 0.40)

    /// A friendly average face, used as the base for default characters and as a fallback
    /// when a landmark from Vision looks implausible.
    static func standardShape(jawWidth: CGFloat = 1.0,
                              chinDrop: CGFloat = 0.0,
                              noseLength: CGFloat = 0.0,
                              mouthWidth: CGFloat = 0.19) -> FaceShape {
        let chinV = 0.80 + chinDrop
        var contour: [CGPoint] = []
        let n = 17
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1)          // 0 ... 1
            let theta = t * .pi                           // ear → chin → ear
            let halfW = 0.31 * jawWidth * (1 - 0.18 * sin(theta))
            let u = 0.5 - halfW * cos(theta)
            let v = 0.43 + (chinV - 0.43) * pow(sin(theta), 0.8)
            contour.append(CGPoint(x: u, y: v))
        }
        return FaceShape(leftEye: FaceLayout.leftEye,
                         rightEye: FaceLayout.rightEye,
                         noseTip: CGPoint(x: 0.5, y: 0.555 + noseLength),
                         mouthCenter: CGPoint(x: 0.5, y: 0.675 + chinDrop * 0.4),
                         mouthWidth: mouthWidth,
                         chin: CGPoint(x: 0.5, y: chinV),
                         contour: contour)
    }

    /// Keeps a measured shape inside sane bounds so a bad landmark can't produce a monster
    /// (well — not an *unintentional* monster).
    static func sanitized(_ s: FaceShape) -> FaceShape {
        var out = s
        let std = standardShape()
        func clamp(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(x, lo), hi) }
        out.noseTip.x = clamp(s.noseTip.x, 0.42, 0.58)
        out.noseTip.y = clamp(s.noseTip.y, 0.48, 0.62)
        out.mouthCenter.x = clamp(s.mouthCenter.x, 0.42, 0.58)
        out.mouthCenter.y = clamp(s.mouthCenter.y, out.noseTip.y + 0.05, 0.76)
        out.mouthWidth = clamp(s.mouthWidth, 0.12, 0.30)
        out.chin.x = clamp(s.chin.x, 0.40, 0.60)
        out.chin.y = clamp(s.chin.y, out.mouthCenter.y + 0.06, 0.92)
        if s.contour.count < 5 { out.contour = std.contour }
        return out
    }
}
