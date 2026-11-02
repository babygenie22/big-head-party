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
/// 0. `touchUp` gives every photo flattering, even light first, and `evenLighting` takes the
///    photo's own side or top light off the face (see there). With a depth photo, the measured
///    face shape is kept too (`DepthRelief`).
/// 1. A similarity transform (rotate + scale + move) puts the pupils exactly on the canonical
///    eye positions. No non-rigid warping, so the person's real proportions survive; the mesh
///    adapts to *them* instead (see `HeadMeshBuilder`).
/// 2. Person segmentation removes the photo background; a feathered oval keeps face + hair.
/// 3. Skin and hair colors sampled from the photo fill the rest of the head (sides, back, crown)
///    so the photo blends into a complete 3D head.
enum FaceTextureBuilder {
    /// Default (linear) working space: the touch-up was tuned there, and in gamma sRGB the shadow
    /// lift turned dark brown irises grey-blue.
    static let ciContext = CIContext()

    static func build(from capture: FaceCapture) -> BuiltFace {
        let T = FaceLayout.photoTextureSize
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
        func halfExtent(_ pts: [CGPoint], _ axis: KeyPath<CGPoint, CGFloat>) -> CGFloat? {
            guard let lo = pts.map({ $0[keyPath: axis] }).min(), let hi = pts.map({ $0[keyPath: axis] }).max() else { return nil }
            return (hi - lo) / 2
        }
        func mean(_ xs: [CGFloat]) -> CGFloat? { xs.isEmpty ? nil : xs.reduce(0, +) / CGFloat(xs.count) }
        let browVs = capture.eyebrows.flatMap { $0.map(uv) }.map(\.y)
        let eyesUV = capture.eyeOutlines.map { $0.map(uv) }
        var shape = FaceLayout.sanitized(FaceShape(leftEye: FaceLayout.leftEye,
                                                   rightEye: FaceLayout.rightEye,
                                                   noseTip: noseTip,
                                                   mouthCenter: mouth,
                                                   mouthWidth: lipsMaxX - lipsMinX,
                                                   chin: chin,
                                                   contour: contourUV,
                                                   browLift: mean(browVs).map { FaceLayout.leftEye.y - $0 },
                                                   eyeHalfWidth: mean(eyesUV.compactMap { halfExtent($0, \.x) }),
                                                   eyeHalfHeight: mean(eyesUV.compactMap { halfExtent($0, \.y) }),
                                                   noseHalfWidth: halfExtent(noseUV, \.x),
                                                   lipHeight: halfExtent(lipsUV, \.y).map { $0 * 2 }))

        // Measured shape from a depth photo: the real nose, brows, lips and cheeks.
        if let depth = capture.depth {
            let toPhoto = align.inverted()
            let w = CGFloat(capture.image.width), h = CGFloat(capture.image.height)
            shape.depthRelief = DepthRelief.build(depth: depth, shape: shape) { uv in
                let p = ciPoint(uv: uv).applying(toPhoto)
                return CGPoint(x: p.x / w, y: 1 - p.y / h)
            }
        }

        // ---- Aligned photo, mask and sampled colors --------------------------------
        let photo = evenLighting(touchUp(CIImage(cgImage: capture.image), pupils: [capture.eyes.0, capture.eyes.1]).transformed(by: align),
                                 shape: shape, canvas: canvas)
        let black = CIImage(color: .black).cropped(to: canvas)

        var personMask: CIImage?
        if let pb = capture.personMask {
            let raw = CIImage(cvPixelBuffer: pb)
            let toImage = CGAffineTransform(scaleX: CGFloat(capture.image.width) / raw.extent.width,
                                            y: CGFloat(capture.image.height) / raw.extent.height)
            personMask = raw.transformed(by: toImage.concatenating(align)).composited(over: black).cropped(to: canvas)
        }
        // A usable person mask must cover the middle of the face; otherwise ignore it rather than
        // erase the photo (the Simulator, and some unusual photos, return an empty mask).
        if let mask = personMask,
           let cover = averageColor(of: mask, in: [ciRect(u: 0.38, v: 0.38, w: 0.24, h: 0.3)])?.rgba.r, cover < 0.5 {
            personMask = nil
        }

        // Cheeks and forehead: the cheeks alone sit in the nose's shadow and read too dark.
        let skin = averageColor(of: photo, in: [ciRect(u: 0.31, v: 0.50, w: 0.06, h: 0.05),
                                                ciRect(u: 0.63, v: 0.50, w: 0.06, h: 0.05),
                                                ciRect(u: 0.45, v: 0.22, w: 0.10, h: 0.05)])
            ?? UIColor(red: 0.85, green: 0.68, blue: 0.56, alpha: 1)
        let detectedHair = hairColor(photo: photo, mask: personMask, skin: skin)
        let hair = detectedHair ?? skin.darker(0.8)

        // ---- Composite ---------------------------------------------------------------
        // The photo oval follows THIS face: its fade lands on the measured jawline and chin. A fixed
        // oval reached past narrow faces onto the sides of the head, where a frontal photo smears.
        // (The gradient is solid to 0.78 of the radius and gone at 1.0, so 0.89 is the fade's middle.)
        let jawHalfWidth = shape.contour.map { abs($0.x - shape.midlineU) }.max() ?? 0.28
        let rx = min(max(jawHalfWidth / 0.92, 0.24), 0.34)
        let ry = min(max((shape.chin.y + 0.02 - 0.41) / 0.89, 0.40), 0.56)
        var mask = ellipseMask(center: ciPoint(uv: CGPoint(x: shape.midlineU, y: 0.41)), rx: rx * T, ry: ry * T, canvas: canvas)
        if let personMask {
            // Pull the cut-out in a touch and soften it: a hard silhouette left a line down the
            // side of the head where the photo met the fill.
            let soft = personMask
                .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 0.004 * T])
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.008 * T])
                .cropped(to: canvas)
            mask = soft.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        }
        // Flat skin, then the photo's own colours carried past its edge, then hair on top so the
        // crown and back stay hair even where the photo's skin colour spreads.
        let layers = fillLayers(skin: skin, hair: detectedHair, size: T)
        var fill = extendColors(of: photo, mask: mask, canvas: canvas).composited(over: CIImage(cgImage: layers.skin))
        if let hairLayer = layers.hair { fill = CIImage(cgImage: hairLayer).composited(over: fill) }
        let composed = photo
            .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: fill,
                                                            kCIInputMaskImageKey: mask])
            .composited(over: fill)
            .cropped(to: canvas)

        let cgOut = ciContext.createCGImage(composed, from: canvas) ?? fillCG(skin: skin)
        return BuiltFace(texture: UIImage(cgImage: cgOut), shape: shape, skin: skin, hair: hair)
    }

    // MARK: - Pieces

    /// A gentle automatic retouch so people like how they look: Core Image's own auto-enhance
    /// (face-aware color balance, tone curve, vibrance, shadows) at 75% so it stays natural,
    /// calmer shine, a little noise cleanup, crisper detail, and concealer under the eyes that
    /// lifts only as much as the under-eyes are darker than the cheeks (none on a well-lit face).
    /// `pupils` are in image pixels, bottom-left origin (Vision and Core Image agree).
    static func touchUp(_ image: CIImage, pupils: [CGPoint]) -> CIImage {
        let clean = image.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": 0.015, "inputSharpness": 0.5])
        var auto = clean
        for filter in clean.autoAdjustmentFilters(options: [.redEye: false]) {
            filter.setValue(auto, forKey: kCIInputImageKey)
            auto = filter.outputImage ?? auto
        }
        var out = clean.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": auto, "inputTime": 0.75])
        out = out.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": 0.8, "inputShadowAmount": 0.35])
        out = out.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.35, "inputRadius": 1.5])

        guard pupils.count == 2 else { return out.cropped(to: image.extent) }
        let ipd = hypot(pupils[1].x - pupils[0].x, pupils[1].y - pupils[0].y)
        // Keep the eyes' own colour: lifting shadows and balancing skin tones greys out dark irises.
        var irises = CIImage(color: .black).cropped(to: image.extent)
        for p in pupils {
            guard let dot = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: p.x, y: p.y), "inputRadius0": ipd * 0.08, "inputRadius1": ipd * 0.13,
                "inputColor0": CIColor.white, "inputColor1": CIColor.black,
            ])?.outputImage else { continue }
            irises = dot.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: irises])
        }
        out = clean.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: out,
                                                                    kCIInputMaskImageKey: irises.cropped(to: image.extent)])
        func luminance(at c: CGPoint) -> CGFloat {
            let r = ipd * 0.12
            let rect = CGRect(x: c.x - r, y: c.y - r / 2, width: 2 * r, height: r)
            guard let avg = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: out, kCIInputExtentKey: CIVector(cgRect: rect)])?.outputImage
            else { return 1 }
            var px = [UInt8](repeating: 0, count: 4)
            ciContext.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                             format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return max(0.02, (0.3 * CGFloat(px[0]) + 0.59 * CGFloat(px[1]) + 0.11 * CGFloat(px[2])) / 255)
        }
        let gap = pupils.map { p in
            log2(luminance(at: CGPoint(x: p.x, y: p.y - ipd * 0.55)) / luminance(at: CGPoint(x: p.x, y: p.y - ipd * 0.24)))
        }.reduce(0, +) / 2
        let ev = min(max(gap * 1.3, 0), 0.75)
        guard ev > 0.02 else { return out.cropped(to: image.extent) }

        var mask = CIImage(color: .black).cropped(to: image.extent)
        for p in pupils {
            guard let crescent = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: 0, y: 0), "inputRadius0": 0.5, "inputRadius1": 1.0,
                "inputColor0": CIColor(red: 0.9, green: 0.9, blue: 0.9), "inputColor1": CIColor.black,
            ])?.outputImage else { continue }
            mask = crescent
                .transformed(by: CGAffineTransform(scaleX: ipd * 0.34, y: ipd * 0.17)
                    .concatenating(CGAffineTransform(translationX: p.x, y: p.y - ipd * 0.24)))
                .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        }
        let lifted = out.applyingFilter("CIExposureAdjust", parameters: ["inputEV": ev])
        return lifted
            .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: out, kCIInputMaskImageKey: mask.cropped(to: image.extent)])
            .cropped(to: image.extent)
    }

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

    /// Carries the photo's own colours a little way past its edge (a normalized blur: the average
    /// of nearby photo pixels, weighted by the mask), so the temples, sideburns and jaw fade into
    /// matching skin and hair instead of meeting a flat fill colour.
    private static func extendColors(of photo: CIImage, mask: CIImage, canvas: CGRect) -> CIImage {
        let clear = CIImage(color: .clear).cropped(to: canvas)
        let cut = photo.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: clear,
                                                                       kCIInputMaskImageKey: mask])
        var out = clear
        for (radius, gain) in [(CGFloat(0.08), CGFloat(3)), (0.025, 4)] {
            let layer = cut
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * canvas.width])
                .cropped(to: canvas)
                // RGB stays the weighted average; alpha (coverage) is boosted so it fades out late.
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: gain)])
                .applyingFilter("CIColorClamp")
            out = layer.composited(over: out)
        }
        return out
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

    /// Flat skin, plus (if they have any) a hair layer over the crown and down the back to a nape
    /// that curves up behind the ears. The back of the head samples the texture's outer columns
    /// from both sides (u → 0 and u → 1 meet at the back), so hair is drawn for the left half and
    /// mirrored: no seam back there.
    private static func fillLayers(skin: UIColor, hair: UIColor?, size T: CGFloat) -> (skin: CGImage, hair: CGImage?) {
        let px = T / 1024   // tuned at 1024²
        let canvas = CGRect(x: 0, y: 0, width: T, height: T)
        let opaque = UIGraphicsImageRendererFormat()
        opaque.scale = 1
        opaque.opaque = true
        // Photos carry soft shading; flat fill reads brighter than the face.
        let skinImage = UIGraphicsImageRenderer(size: canvas.size, format: opaque).image { ctx in
            skin.darker(0.95).setFill(); ctx.fill(canvas)
        }.cgImage!
        guard let hair else { return (skinImage, nil) }

        // One outline (overlapping sub-shapes cancel out under the non-zero fill rule).
        let hairShape = CGMutablePath()
        hairShape.move(to: CGPoint(x: 0, y: 0))
        hairShape.addLine(to: CGPoint(x: T / 2, y: 0))
        hairShape.addLine(to: CGPoint(x: T / 2, y: 0.19 * T))
        hairShape.addLine(to: CGPoint(x: 0.19 * T, y: 0.19 * T))
        hairShape.addLine(to: CGPoint(x: 0.19 * T, y: 0.47 * T))
        hairShape.addCurve(to: CGPoint(x: 0, y: 0.70 * T),
                           control1: CGPoint(x: 0.15 * T, y: 0.56 * T), control2: CGPoint(x: 0.09 * T, y: 0.70 * T))
        hairShape.closeSubpath()

        let clearFormat = UIGraphicsImageRendererFormat()
        clearFormat.scale = 1
        clearFormat.opaque = false
        // Soft-edged coverage...
        let hard = UIGraphicsImageRenderer(size: canvas.size, format: clearFormat).image { ctx in
            ctx.cgContext.addPath(hairShape)
            ctx.cgContext.setFillColor(hair.cgColor)
            ctx.cgContext.fillPath()
        }
        let soft = CIImage(cgImage: hard.cgImage!)
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 22 * px])
            .cropped(to: canvas)
        let softCG = ciContext.createCGImage(soft, from: canvas) ?? hard.cgImage!
        // ...then strands, clipped to the same shape.
        var rng = SeededRandom(seed: 17)
        let detailed = UIGraphicsImageRenderer(size: canvas.size, format: clearFormat).image { ctx in
            UIImage(cgImage: softCG).draw(in: canvas)
            HairStrands.draw(in: ctx.cgContext, color: hair, region: hairShape, count: Int(1700 * px * px), rng: &rng, size: T)
        }.cgImage!
        // Left half, mirrored onto the right.
        let half = detailed.cropping(to: CGRect(x: 0, y: 0, width: T / 2, height: T))!
        let mirrored = UIGraphicsImageRenderer(size: canvas.size, format: clearFormat).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: 0, y: T); c.scaleBy(x: 1, y: -1)   // CG draws images bottom-up
            c.draw(half, in: CGRect(x: 0, y: 0, width: T / 2, height: T))
            c.translateBy(x: T, y: 0); c.scaleBy(x: -1, y: 1)
            c.draw(half, in: CGRect(x: 0, y: 0, width: T / 2, height: T))
        }.cgImage
        return (skinImage, mirrored ?? detailed)
    }

    /// Hair = person pixels above the brows that are clearly not skin. Too few means bald (nil).
    private static func hairColor(photo: CIImage, mask: CIImage?, skin: UIColor) -> UIColor? {
        let T = FaceLayout.photoTextureSize
        let region = CGRect(x: 0.2 * T, y: 0.7 * T, width: 0.6 * T, height: 0.3 * T)   // top 30% of the texture (CI is bottom-up)
        let w = Int(region.width), h = Int(region.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        ciContext.render(photo, toBitmap: &px, rowBytes: w * 4, bounds: region, format: .RGBA8, colorSpace: space)
        var mk: [UInt8]?
        if let mask {
            var m = [UInt8](repeating: 0, count: w * h * 4)
            ciContext.render(mask, toBitmap: &m, rowBytes: w * 4, bounds: region, format: .RGBA8, colorSpace: space)
            mk = m
        }
        let s = skin.rgba
        let skinLum = 0.3 * s.r + 0.59 * s.g + 0.11 * s.b
        var hairPx: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [], person = 0
        for i in stride(from: 0, to: px.count, by: 16) {
            guard px[i + 3] > 250 else { continue }
            if let mk, mk[i] < 128 { continue }
            person += 1
            let r = CGFloat(px[i]) / 255, g = CGFloat(px[i + 1]) / 255, b = CGFloat(px[i + 2]) / 255
            let lum = 0.3 * r + 0.59 * g + 0.11 * b
            let dist = ((r - s.r) * (r - s.r) + (g - s.g) * (g - s.g) + (b - s.b) * (b - s.b)).squareRoot()
            if dist > 0.22 && abs(lum - skinLum) > 0.12 { hairPx.append((r, g, b)) }
        }
        guard hairPx.count > max(30, person / 25) else { return nil }
        // Median, not mean: shine, grey strands and soft mask edges pulled the mean light brown.
        func median(_ xs: [CGFloat]) -> CGFloat { xs.sorted()[xs.count / 2] }
        // A shade deeper: hair seen in the photo is lifted by the touch-up and its own shine.
        return UIColor(red: median(hairPx.map(\.r)), green: median(hairPx.map(\.g)), blue: median(hairPx.map(\.b)), alpha: 1).darker(0.8)
    }

    private static func fillCG(skin: UIColor) -> CGImage {
        let T = FaceLayout.photoTextureSize
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
