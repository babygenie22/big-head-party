import UIKit
import CoreImage
import SceneKit
import simd

/// A photo of one side of the head, and how it lines up with the 3D head: the head turned by
/// `yaw` and seen through a simple camera (scale, tilt, shift). One front photo can't show the
/// cheeks, jaw and temples side-on, so it smears there; a side photo fills them in for real.
struct SideView: Codable, Equatable {
    /// How far the head is turned in the photo (radians). The sign says which side it shows.
    var yaw: Float
    /// Model → texture pixels (top-left origin): pixel = a · (x′ − i·y) + b as complex numbers,
    /// with x′ = x·cos(yaw) + z·sin(yaw). `a` carries the scale and tilt, `b` the shift.
    var a: [Float]
    var b: [Float]
    var size: [Float]

    /// Which side of the model this photo shows: −1 the −x side, +1 the +x side.
    var side: Int { yaw > 0 ? -1 : 1 }

    /// Direction from the head to the camera, in model space.
    var toCamera: SIMD3<Float> { SIMD3(-sin(yaw), 0, cos(yaw)) }

    /// Where a point of the head lands in the side texture, as a 0...1 texture coordinate.
    func uv(_ p: SIMD3<Float>) -> SIMD2<Float> {
        let x = p.x * cos(yaw) + p.z * sin(yaw), y = -p.y
        return SIMD2((a[0] * x - a[1] * y + b[0]) / size[0], (a[1] * x + a[0] * y + b[1]) / size[1])
    }

    /// How much of this photo to show at a point with this surface normal: where the side
    /// camera sees the skin more squarely than the front camera did (and sees it at all).
    func weight(normal n: SIMD3<Float>) -> Float {
        let facing = simd_dot(n, toCamera)
        return smoothStep(0.05, 0.35, facing - n.z) * smoothStep(0.15, 0.4, facing)
    }
}

enum SideFitError: LocalizedError {
    case notTurned, noMatch

    var errorDescription: String? {
        switch self {
        case .notTurned: return "That looks like a front photo. Turn the head about halfway to one side and try again."
        case .noMatch: return "We couldn't line that photo up with the head. Try again with the head turned about halfway, in good light."
        }
    }
}

enum SideFit {
    /// Lines a turned-head photo up with a sculpted head and cuts out the texture for that side.
    /// `frontTexture` is the head's own texture, used to match the two photos' colour.
    static func build(capture: FaceCapture, shape rawShape: FaceShape, head: HeadMeshBuilder.Output, frontTexture: CGImage?) throws -> (view: SideView, texture: UIImage) {
        let shape = FaceLayout.sanitized(rawShape)
        guard let vSource = head.geometry.sources(for: .vertex).first, let nSource = head.geometry.sources(for: .normal).first,
              let uvSource = head.geometry.sources(for: .texcoord).first else { throw SideFitError.noMatch }
        let positions = vSource.vectors, normals = nSource.vectors
        let H = Float(capture.image.height)

        // The same landmarks on the head (3D) and in the photo (pixels, top-left origin).
        func onFace(_ uv: CGPoint) -> SIMD3<Float> {
            let x = HeadMeshBuilder.modelX(u: uv.x), y = HeadMeshBuilder.modelY(v: uv.y)
            var best = SIMD3<Float>(x, y, 0.9), bestD = Float.infinity
            for k in positions.indices where normals[k].z > 0.3 {
                let d = (positions[k].x - x) * (positions[k].x - x) + (positions[k].y - y) * (positions[k].y - y)
                if d < bestD { bestD = d; best = SIMD3(x, y, positions[k].z) }
            }
            return best
        }
        func pixel(_ p: CGPoint) -> SIMD2<Float> { SIMD2(Float(p.x), H - Float(p.y)) }
        func centroid(_ pts: [CGPoint]) -> CGPoint? {
            pts.isEmpty ? nil : CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count), y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count))
        }
        var pairs: [(model: SIMD3<Float>, photo: SIMD2<Float>, weight: Float)] = [
            (onFace(shape.leftEye), pixel(capture.eyes.0), 2), (onFace(shape.rightEye), pixel(capture.eyes.1), 2),
        ]
        if let lips = centroid(capture.outerLips) { pairs.append((onFace(shape.mouthCenter), pixel(lips), 1)) }
        if let noseX = centroid(capture.nose)?.x, let noseY = capture.nose.map(\.y).min() {
            pairs.append((onFace(shape.noseTip), pixel(CGPoint(x: noseX, y: noseY)), 1))
        }
        if let chin = capture.contour.min(by: { $0.y < $1.y }) { pairs.append((onFace(shape.chin), pixel(chin), 1)) }
        guard pairs.count >= 4 else { throw SideFitError.noMatch }

        // How far the head is turned: turning squeezes the eyes together in the picture but leaves
        // the eye-to-mouth height alone, so their ratio against the same ratio on the head gives
        // the angle. (Fitting the angle to all the landmarks at once was fooled by the nose and
        // chin, which sit differently on a turned face.) The nose says which way.
        guard let lips = centroid(capture.outerLips), let nose = centroid(capture.nose) else { throw SideFitError.noMatch }
        let eyeL = pixel(capture.eyes.0), eyeR = pixel(capture.eyes.1), eyeMid = (eyeL + eyeR) / 2
        let across = simd_normalize(eyeR - eyeL), down = SIMD2(-across.y, across.x)
        let eyeGap = simd_length(eyeR - eyeL), drop = abs(simd_dot(pixel(lips) - eyeMid, down))
        let headGap = HeadMeshBuilder.modelX(u: shape.rightEye.x) - HeadMeshBuilder.modelX(u: shape.leftEye.x)
        let headDrop = HeadMeshBuilder.modelY(v: shape.eyeLineV) - HeadMeshBuilder.modelY(v: shape.mouthCenter.y)
        guard drop > 1, headDrop > 0.05, headGap > 0.05 else { throw SideFitError.noMatch }
        let squeeze = (eyeGap / drop) / (headGap / headDrop)
        guard squeeze < cos(20 * Float.pi / 180) else { throw SideFitError.notTurned }
        let turn = acos(max(squeeze, cos(70 * Float.pi / 180)))
        let yaw = simd_dot(pixel(nose) - eyeMid, across) >= 0 ? turn : -turn

        // With the turn known, the best scale, tilt and shift have a closed form.
        let total = pairs.map(\.weight).reduce(0, +)
        let m = pairs.map { SIMD2($0.model.x * cos(yaw) + $0.model.z * sin(yaw), -$0.model.y) }
        let mMean = zip(m, pairs).map { $0 * $1.weight }.reduce(.zero, +) / total
        let qMean = pairs.map { $0.photo * $0.weight }.reduce(.zero, +) / total
        var num = SIMD2<Float>.zero, den: Float = 0, spread: Float = 0
        for (mi, pair) in zip(m, pairs) {
            let dm = mi - mMean, dq = pair.photo - qMean
            // (dq) · conj(dm) as complex numbers.
            num += SIMD2(dq.x * dm.x + dq.y * dm.y, dq.y * dm.x - dq.x * dm.y) * pair.weight
            den += simd_length_squared(dm) * pair.weight
            spread += simd_length_squared(dq) * pair.weight
        }
        guard den > 1e-6, spread > 1e-6 else { throw SideFitError.noMatch }
        let a = num / den
        let b = qMean - SIMD2(a.x * mMean.x - a.y * mMean.y, a.y * mMean.x + a.x * mMean.y)
        var error: Float = 0
        for (mi, pair) in zip(m, pairs) {
            let predicted = SIMD2(a.x * mi.x - a.y * mi.y, a.y * mi.x + a.x * mi.y) + b
            error += simd_length_squared(predicted - pair.photo) * pair.weight
        }
        // Heads aren't sideways, and the landmarks should land close to where the head puts them.
        guard abs(atan2(a.y, a.x)) < 0.5, error / spread < 0.06 else { throw SideFitError.noMatch }
        var view = SideView(yaw: yaw, a: [a.x, a.y], b: [b.x, b.y], size: [Float(capture.image.width), H])

        // ---- The texture: the part of the photo the head covers, cut out from the background.
        var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
        for k in positions.indices where view.weight(normal: normals[k]) > 0 {
            let p = view.uv(positions[k]) * SIMD2(view.size[0], view.size[1])
            lo = simd_min(lo, p); hi = simd_max(hi, p)
        }
        guard lo.x < hi.x, lo.y < hi.y else { throw SideFitError.noMatch }
        let pad = (hi - lo) * 0.06
        lo = simd_max(lo - pad, .zero)
        hi = simd_min(hi + pad, SIMD2(view.size[0], view.size[1]))
        guard hi.x - lo.x > 32, hi.y - lo.y > 32 else { throw SideFitError.noMatch }
        let k = min(1, 1280 / max(hi.x - lo.x, hi.y - lo.y))

        let full = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)
        var photo = FaceTextureBuilder.touchUp(CIImage(cgImage: capture.image), pupils: [capture.eyes.0, capture.eyes.1])
        if let gain = colourMatch(photo: photo, view: view, positions: positions, normals: normals, uvs: uvSource, front: frontTexture) {
            photo = photo.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(gain.x), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(gain.y), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(gain.z), w: 0),
            ])
        }
        if let pb = capture.personMask {
            let raw = CIImage(cvPixelBuffer: pb)
            let mask = raw
                .transformed(by: CGAffineTransform(scaleX: full.width / raw.extent.width, y: full.height / raw.extent.height))
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: full.width * 0.004])
                .cropped(to: full)
            photo = photo.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: full),
                                                                         kCIInputMaskImageKey: mask])
        }
        // Core Image is bottom-up; the crop is in top-left pixels.
        let crop = CGRect(x: CGFloat(lo.x), y: CGFloat(H - hi.y), width: CGFloat(hi.x - lo.x), height: CGFloat(hi.y - lo.y))
        let out = photo.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY).concatenating(CGAffineTransform(scaleX: CGFloat(k), y: CGFloat(k))))
        let outRect = CGRect(x: 0, y: 0, width: (crop.width * CGFloat(k)).rounded(.down), height: (crop.height * CGFloat(k)).rounded(.down))
        guard let cg = FaceTextureBuilder.ciContext.createCGImage(out, from: outRect) else { throw SideFitError.noMatch }
        view.a = [view.a[0] * k, view.a[1] * k]
        view.b = [(view.b[0] - lo.x) * k, (view.b[1] - lo.y) * k]
        view.size = [Float(outRect.width), Float(outRect.height)]
        return (view, UIImage(cgImage: cg))
    }

    /// Per-channel gain that brings the side photo's skin to the front texture's, measured where
    /// both photos see the same skin (the front of the cheek). Nil when it can't be measured.
    private static func colourMatch(photo: CIImage, view: SideView, positions: [SIMD3<Float>], normals: [SIMD3<Float>],
                                    uvs: SCNGeometrySource, front: CGImage?) -> SIMD3<Float>? {
        guard let front, let frontPx = Bitmap(front, width: 256),
              let sideCG = FaceTextureBuilder.ciContext.createCGImage(photo, from: photo.extent), let sidePx = Bitmap(sideCG, width: 256) else { return nil }
        let frontUV = uvs.pairs
        guard frontUV.count == positions.count else { return nil }
        var a = SIMD3<Float>.zero, b = SIMD3<Float>.zero, n = 0
        for k in stride(from: 0, to: positions.count, by: 7) {
            let nrm = normals[k]
            guard nrm.z > 0.5, nrm.z < 0.85, simd_dot(nrm, view.toCamera) > 0.5, abs(nrm.y) < 0.5 else { continue }
            let s = view.uv(positions[k])
            guard let fc = frontPx.color(u: frontUV[k].x, v: frontUV[k].y), let sc = sidePx.color(u: s.x, v: s.y) else { continue }
            a += fc; b += sc; n += 1
        }
        guard n > 20, b.min() > 0.02 else { return nil }
        return simd_clamp(a / b, SIMD3(repeating: 0.7), SIMD3(repeating: 1.45))
    }
}

extension SCNGeometrySource {
    /// The source's 2D vectors (texture coordinates).
    var pairs: [SIMD2<Float>] {
        data.withUnsafeBytes { raw in
            (0..<vectorCount).map { i in
                let o = dataOffset + i * dataStride
                if bytesPerComponent == 8 {
                    return SIMD2(Float(raw.loadUnaligned(fromByteOffset: o, as: Double.self)), Float(raw.loadUnaligned(fromByteOffset: o + 8, as: Double.self)))
                }
                return SIMD2(raw.loadUnaligned(fromByteOffset: o, as: Float.self), raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self))
            }
        }
    }
}

/// A small RGBA copy of an image, for reading colours at texture coordinates (v from the top).
private struct Bitmap {
    let width: Int, height: Int
    let px: [UInt8]

    init?(_ image: CGImage, width w: Int) {
        let h = max(1, w * image.height / max(image.width, 1))
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        width = w; height = h; px = data
    }

    func color(u: Float, v: Float) -> SIMD3<Float>? {
        guard u >= 0, v >= 0, u < 1, v < 1 else { return nil }
        let k = (Int(v * Float(height)) * width + Int(u * Float(width))) * 4
        guard px[k + 3] > 200 else { return nil }
        return SIMD3(Float(px[k]), Float(px[k + 1]), Float(px[k + 2])) / 255
    }
}
