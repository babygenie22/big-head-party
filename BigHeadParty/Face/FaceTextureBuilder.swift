import UIKit
import CoreImage

/// The result of turning a photo into game-ready face data.
struct BuiltFace {
    let texture: UIImage
    let shape: FaceShape
    let skin: UIColor
    let hair: UIColor
}

/// Warps a photo into the head's texture space.
///
/// 1. A similarity transform (rotate + scale + move) puts the pupils exactly on the canonical
///    eye positions. No non-rigid warping, so the person's real proportions survive; the mesh
///    adapts to *them* instead (see `HeadMeshBuilder`).
/// 2. Person segmentation removes the photo background; a feathered oval keeps face + hair.
/// 3. Skin and hair colors sampled from the photo fill the rest of the head (sides, back, crown)
///    so the photo blends into a complete 3D head.
enum FaceTextureBuilder {
    static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any])

    static func build(from capture: FaceCapture) -> BuiltFace {
        let T = FaceLayout.textureSize
        let canvas = CGRect(x: 0, y: 0, width: T, height: T)
        // Core Image space is bottom-left origin, like Vision.
        func ciPoint(uv: CGPoint) -> CGPoint { CGPoint(x: uv.x * T, y: (1 - uv.y) * T) }
        func ciRect(u: CGFloat, v: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
            CGRect(x: u * T, y: (1 - v - h) * T, width: w * T, height: h * T)
        }

        let align = similarity(from: capture.eyes.0, capture.eyes.1,
                               to: ciPoint(uv: FaceLayout.leftEye), ciPoint(uv: FaceLayout.rightEye))
        func uv(_ p: CGPoint) -> CGPoint {
            let q = p.applying(align)
            return CGPoint(x: q.x / T, y: 1 - q.y / T)
        }

        // ---- Measured face shape ----------------------------------------------------
        let noseUV = capture.nose.map(uv)
        let lipsUV = capture.outerLips.map(uv)
        let contourUV = capture.contour.map(uv)
        let noseTip = CGPoint(x: noseUV.map(\.x).reduce(0, +) / CGFloat(noseUV.count),
                              y: (noseUV.map(\.y).max() ?? 0.57) - 0.015)
        let lipsMinX = lipsUV.map(\.x).min() ?? 0.4, lipsMaxX = lipsUV.map(\.x).max() ?? 0.6
        let mouth = CGPoint(x: lipsUV.map(\.x).reduce(0, +) / CGFloat(lipsUV.count),
                            y: lipsUV.map(\.y).reduce(0, +) / CGFloat(lipsUV.count))
        let chin = contourUV.max(by: { $0.y < $1.y }) ?? CGPoint(x: 0.5, y: 0.8)
        let shape = FaceLayout.sanitized(FaceShape(leftEye: FaceLayout.leftEye,
                                                   rightEye: FaceLayout.rightEye,
                                                   noseTip: noseTip,
                                                   mouthCenter: mouth,
                                                   mouthWidth: lipsMaxX - lipsMinX,
                                                   chin: chin,
                                                   contour: contourUV))

        // ---- Aligned photo, mask and sampled colors --------------------------------
        let photo = CIImage(cgImage: capture.image).transformed(by: align)
        let black = CIImage(color: .black).cropped(to: canvas)

        var personMask: CIImage?
        if let pb = capture.personMask {
            let raw = CIImage(cvPixelBuffer: pb)
            let toImage = CGAffineTransform(scaleX: CGFloat(capture.image.width) / raw.extent.width,
                                            y: CGFloat(capture.image.height) / raw.extent.height)
            personMask = raw.transformed(by: toImage.concatenating(align)).composited(over: black).cropped(to: canvas)
        }

        let skin = averageColor(of: photo, in: [ciRect(u: 0.33, v: 0.53, w: 0.06, h: 0.05),
                                                ciRect(u: 0.61, v: 0.53, w: 0.06, h: 0.05)])
            ?? UIColor(red: 0.85, green: 0.68, blue: 0.56, alpha: 1)
        let hairRect = ciRect(u: 0.42, v: 0.07, w: 0.16, h: 0.07)
        var hair = averageColor(of: photo, in: [hairRect]) ?? skin.darker(0.5)
        if let mask = personMask, let coverage = averageColor(of: mask, in: [hairRect])?.rgba.r, coverage < 0.5 {
            hair = skin.darker(0.8)   // nothing above the forehead: bald, or hair cropped off
        }

        // ---- Composite ---------------------------------------------------------------
        let fill = CIImage(cgImage: fillImage(skin: skin, hair: hair))
        var mask = ellipseMask(center: ciPoint(uv: CGPoint(x: 0.5, y: 0.41)), rx: 0.31 * T, ry: 0.44 * T, canvas: canvas)
        if let personMask {
            mask = personMask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        }
        let composed = photo
            .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: fill,
                                                            kCIInputMaskImageKey: mask])
            .composited(over: fill)
            .cropped(to: canvas)

        let cgOut = ciContext.createCGImage(composed, from: canvas) ?? fillCG(skin: skin)
        return BuiltFace(texture: UIImage(cgImage: cgOut), shape: shape, skin: skin, hair: hair)
    }

    // MARK: - Pieces

    /// Rotation + uniform scale + translation mapping a1→b1 and a2→b2.
    static func similarity(from a1: CGPoint, _ a2: CGPoint, to b1: CGPoint, _ b2: CGPoint) -> CGAffineTransform {
        let da = CGPoint(x: a2.x - a1.x, y: a2.y - a1.y)
        let db = CGPoint(x: b2.x - b1.x, y: b2.y - b1.y)
        let scale = hypot(db.x, db.y) / max(hypot(da.x, da.y), 1)
        let angle = atan2(db.y, db.x) - atan2(da.y, da.x)
        return CGAffineTransform(translationX: -a1.x, y: -a1.y)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: b1.x, y: b1.y))
    }

    private static func ellipseMask(center: CGPoint, rx: CGFloat, ry: CGFloat, canvas: CGRect) -> CIImage {
        let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 0, y: 0),
            "inputRadius0": 0.78,
            "inputRadius1": 1.0,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.black,
        ])?.outputImage ?? CIImage(color: .white)
        return gradient
            .transformed(by: CGAffineTransform(scaleX: rx, y: ry).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
            .cropped(to: canvas)
    }

    private static func averageColor(of image: CIImage, in rects: [CGRect]) -> UIColor? {
        var acc = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0))
        var n: CGFloat = 0
        for rect in rects {
            guard let avg = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image,
                                                                          kCIInputExtentKey: CIVector(cgRect: rect)])?.outputImage
            else { continue }
            var px = [UInt8](repeating: 0, count: 4)
            ciContext.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                             format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            guard px[3] > 0 else { continue }
            let a = CGFloat(px[3]) / 255
            acc.r += CGFloat(px[0]) / 255 / a; acc.g += CGFloat(px[1]) / 255 / a; acc.b += CGFloat(px[2]) / 255 / a
            n += 1
        }
        guard n > 0 else { return nil }
        return UIColor(red: min(acc.r / n, 1), green: min(acc.g / n, 1), blue: min(acc.b / n, 1), alpha: 1)
    }

    /// Skin everywhere, hair on the crown and around the back; softened so it blends.
    private static func fillImage(skin: UIColor, hair: UIColor) -> CGImage {
        let T = FaceLayout.textureSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let hard = UIGraphicsImageRenderer(size: CGSize(width: T, height: T), format: format).image { ctx in
            skin.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: T, height: T))
            hair.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: T, height: 0.16 * T))
            ctx.fill(CGRect(x: 0, y: 0, width: 0.17 * T, height: 0.62 * T))
            ctx.fill(CGRect(x: 0.83 * T, y: 0, width: 0.17 * T, height: 0.62 * T))
        }
        let canvas = CGRect(x: 0, y: 0, width: T, height: T)
        let blurred = CIImage(cgImage: hard.cgImage!)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 28])
            .cropped(to: canvas)
        return ciContext.createCGImage(blurred, from: canvas) ?? hard.cgImage!
    }

    private static func fillCG(skin: UIColor) -> CGImage {
        let T = FaceLayout.textureSize
        return UIGraphicsImageRenderer(size: CGSize(width: T, height: T)).image { ctx in
            skin.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: T, height: T))
        }.cgImage!
    }
}

extension UIColor {
    var rgba: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    func darker(_ factor: CGFloat) -> UIColor {
        let c = rgba
        return UIColor(red: c.r * factor, green: c.g * factor, blue: c.b * factor, alpha: c.a)
    }

    convenience init(rgb: [Float]) {
        let c = rgb + [1, 1, 1]
        self.init(red: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: 1)
    }

    var rgbArray: [Float] {
        let c = rgba
        return [Float(c.r), Float(c.g), Float(c.b)]
    }
}
