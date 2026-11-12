import UIKit
import SceneKit

/// The person's own skin relief, read out of their photo: wrinkles, pores, stubble, brow hairs
/// and lip creases are a little darker than the skin around them, so brightness works as height.
/// Turned into a normal map over the whole head texture, the game's lights catch that detail and
/// it moves with the light as the head turns, instead of staying flat like a printed photo.
enum SkinDetail {
    private static var cache: [UUID: UIImage] = [:]
    private static let lock = NSLock()

    /// The normal map for a character's texture (same UVs as the texture), built once.
    static func normalMap(for character: GameCharacter) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[character.id] { return hit }
        guard let cg = character.texture.cgImage, let map = build(from: cg) else { return nil }
        cache[character.id] = map
        return map
    }

    static func forget(_ id: UUID) {
        lock.lock(); cache[id] = nil; lock.unlock()
    }

    private static func build(from texture: CGImage) -> UIImage? {
        let w = texture.width, h = texture.height
        var gray = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(texture, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Height: brightness, smoothed a touch so sensor noise doesn't sparkle.
        var height = [Float](repeating: 0, count: w * h)
        gray.withUnsafeBufferPointer { g in
            height.withUnsafeMutableBufferPointer { out in
                for y in 0..<h {
                    let y0 = max(y - 1, 0) * w, y1 = y * w, y2 = min(y + 1, h - 1) * w
                    for x in 0..<w {
                        let x0 = max(x - 1, 0), x2 = min(x + 1, w - 1)
                        let sum = Int(g[y0 + x0]) + Int(g[y0 + x]) + Int(g[y0 + x2]) + Int(g[y1 + x0]) + 2 * Int(g[y1 + x])
                            + Int(g[y1 + x2]) + Int(g[y2 + x0]) + Int(g[y2 + x]) + Int(g[y2 + x2])
                        out[y1 + x] = Float(sum) / (10 * 255)
                    }
                }
            }
        }
        // Slopes → normals. Strong edges (brow against skin, the lash line) are held back so
        // they read as soft relief, not engraving. Same channel convention as `skinNormalMap`.
        let strength: Float = 9 * Float(w) / 2048
        var px = [UInt8](repeating: 255, count: w * h * 4)
        height.withUnsafeBufferPointer { hgt in
            px.withUnsafeMutableBufferPointer { out in
                for y in 0..<h {
                    let up = max(y - 1, 0) * w, down = min(y + 1, h - 1) * w, row = y * w
                    for x in 0..<w {
                        var dx = (hgt[row + min(x + 1, w - 1)] - hgt[row + max(x - 1, 0)]) * strength
                        var dy = (hgt[down + x] - hgt[up + x]) * strength
                        let m = (dx * dx + dy * dy).squareRoot()
                        if m > 0.6 { let k = (0.6 + (m - 0.6) * 0.25) / m; dx *= k; dy *= k }
                        let l = (dx * dx + dy * dy + 1).squareRoot()
                        let i = (row + x) * 4
                        out[i] = UInt8(max(0, min(255, (-dx / l * 0.5 + 0.5) * 255)))
                        out[i + 1] = UInt8(max(0, min(255, (-dy / l * 0.5 + 0.5) * 255)))
                        out[i + 2] = UInt8(max(0, min(255, (1 / l * 0.5 + 0.5) * 255)))
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// What a face has been through, on the skin itself: a slap leaves a red handprint that fades
/// over a few seconds, punches leave flushed patches that darken into bruises and stay for the
/// fight, a bonk leaves a red bump of colour. Drawn into one small texture that multiplies the
/// photo, in the texture's own UVs, so marks sit on the right spot and bend with the face.
final class SkinMarks {
    enum Kind { case hand, flush, bruise }

    private struct Mark {
        let kind: Kind
        let center: CGPoint      // texture uv
        let radius: CGFloat      // in uv
        let mirrored: Bool
        var strength: CGFloat
    }

    private var marks: [Mark] = []
    private let size: CGFloat = 512
    private weak var material: SCNMaterial?

    init(material: SCNMaterial) {
        self.material = material
    }

    var isEmpty: Bool { marks.isEmpty }

    func add(_ kind: Kind, at center: CGPoint, radius: CGFloat, strength: CGFloat, mirrored: Bool = false) {
        marks.append(Mark(kind: kind, center: center, radius: radius, mirrored: mirrored, strength: min(1, strength)))
        if marks.count > 14 { marks.removeFirst() }   // old bruises are under newer ones anyway
        redraw()
    }

    /// One step of healing (`dt` seconds): handprints and flushes fade, bruises stay.
    func fade(_ dt: CGFloat) {
        for k in marks.indices {
            switch marks[k].kind {
            case .hand: marks[k].strength -= dt / 9
            case .flush: marks[k].strength -= dt / 6
            case .bruise: break
            }
        }
        marks.removeAll { $0.strength <= 0.02 }
        redraw()
    }

    /// True while something is still fading.
    var isFading: Bool { marks.contains { $0.kind != .bruise } }

    func clear() {
        marks = []
        redraw()
    }

    private func redraw() {
        guard let material else { return }
        guard !marks.isEmpty else {
            material.multiply.contents = UIColor.white
            return
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let T = size
        let image = UIGraphicsImageRenderer(size: CGSize(width: T, height: T), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: T, height: T))
            let c = ctx.cgContext
            for m in marks {
                let p = CGPoint(x: m.center.x * T, y: m.center.y * T), r = m.radius * T
                switch m.kind {
                case .hand:
                    c.saveGState()
                    c.translateBy(x: p.x, y: p.y)
                    c.scaleBy(x: m.mirrored ? -1 : 1, y: 1)
                    c.setAlpha(m.strength)
                    Self.handprint.draw(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
                    c.restoreGState()
                case .flush:
                    Self.blot(c, at: p, radius: r, color: UIColor(red: 1, green: 0.66, blue: 0.62, alpha: m.strength))
                case .bruise:
                    // Red and swollen round the edge, darker and bluer in the middle.
                    Self.blot(c, at: p, radius: r, color: UIColor(red: 0.95, green: 0.62, blue: 0.62, alpha: m.strength * 0.9))
                    Self.blot(c, at: p, radius: r * 0.6, color: UIColor(red: 0.7, green: 0.56, blue: 0.7, alpha: m.strength * 0.7))
                }
            }
        }
        material.multiply.contents = image
        material.multiply.wrapS = .clamp
        material.multiply.wrapT = .clamp
    }

    /// A soft-edged patch of colour.
    private static func blot(_ c: CGContext, at p: CGPoint, radius: CGFloat, color: UIColor) {
        let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.25, 1]) else { return }
        c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
    }

    /// A left hand's print, fingers up and angled across the cheek: palm, four fingers with the
    /// gaps between them still pale, and a thumb. Blotchy rather than solid, like a real one.
    private static let handprint: UIImage = {
        let T: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let red = UIColor(red: 1, green: 0.52, blue: 0.5, alpha: 0.85)
        let sharp = UIGraphicsImageRenderer(size: CGSize(width: T, height: T), format: format).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: T / 2, y: T / 2)
            c.rotate(by: -0.35)
            red.setFill()
            UIBezierPath(roundedRect: CGRect(x: -52, y: 0, width: 104, height: 92), cornerRadius: 38).fill()
            for (k, length) in [CGFloat(78), 96, 102, 88].enumerated() {
                let x = -50 + CGFloat(k) * 26.5
                UIBezierPath(roundedRect: CGRect(x: x, y: 8 - length, width: 21, height: length), cornerRadius: 10).fill()
            }
            c.rotate(by: 0.9)
            UIBezierPath(roundedRect: CGRect(x: 30, y: -8, width: 22, height: 70), cornerRadius: 11).fill()
        }
        guard let input = CIImage(image: sharp) else { return sharp }
        let soft = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 5]).cropped(to: input.extent)
        guard let cg = CIContext().createCGImage(soft, from: input.extent) else { return sharp }
        // Break it up: the heel of the palm and fingertips land hardest.
        return UIGraphicsImageRenderer(size: CGSize(width: T, height: T), format: format).image { ctx in
            UIImage(cgImage: cg).draw(in: CGRect(x: 0, y: 0, width: T, height: T))
            var rng = SeededRandom(seed: 61)
            ctx.cgContext.setBlendMode(.destinationOut)
            for _ in 0..<26 {
                let p = CGPoint(x: CGFloat(rng.next()) * T, y: CGFloat(rng.next()) * T)
                blot(ctx.cgContext, at: p, radius: 10 + CGFloat(rng.next()) * 16, color: UIColor(white: 0, alpha: 0.45))
            }
        }
    }()
}
