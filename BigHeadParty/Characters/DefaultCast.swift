import UIKit

/// The built-in cast. Their faces are painted procedurally into the same texture layout a
/// photo is warped into, so they share every system with player-made heads.
enum DefaultCast {
    enum Hair2D { case full, baldTop, buzz, curl }
    enum Extra { case glasses, monocle, walrusMustache, curledMustache, blush, stubble, eyeshadow, beautyMark, freckles, shades }

    struct Spec {
        let id: String
        let name: String
        let tagline: String
        let skin: UIColor
        let hair: UIColor
        let shirt: UIColor
        let iris: UIColor
        let lips: UIColor
        let hair2D: Hair2D
        let browWeight: CGFloat
        let browColor: UIColor
        let eyeScale: CGFloat
        let extras: [Extra]
        let shape: FaceShape
        let hat: HatStyle
        let volume: HairVolume
    }

    static let specs: [Spec] = [
        Spec(id: "00000000-0000-0000-0000-00000000B001", name: "Grandpa Gus", tagline: "Retired. Undefeated at bingo.",
             skin: UIColor(red: 0.94, green: 0.78, blue: 0.68, alpha: 1), hair: UIColor(white: 0.88, alpha: 1),
             shirt: UIColor(red: 0.55, green: 0.40, blue: 0.30, alpha: 1), iris: UIColor(red: 0.30, green: 0.50, blue: 0.75, alpha: 1),
             lips: UIColor(red: 0.78, green: 0.52, blue: 0.48, alpha: 1), hair2D: .baldTop, browWeight: 1.9,
             browColor: UIColor(white: 0.95, alpha: 1), eyeScale: 0.95, extras: [.glasses, .walrusMustache],
             shape: FaceLayout.standardShape(jawWidth: 1.0, chinDrop: 0.015, noseLength: 0.012), hat: .none, volume: .none),
        Spec(id: "00000000-0000-0000-0000-00000000B002", name: "Aunt Linda", tagline: "Brings a casserole to every fight.",
             skin: UIColor(red: 0.98, green: 0.84, blue: 0.74, alpha: 1), hair: UIColor(red: 0.72, green: 0.24, blue: 0.10, alpha: 1),
             shirt: UIColor(red: 0.55, green: 0.25, blue: 0.65, alpha: 1), iris: UIColor(red: 0.25, green: 0.55, blue: 0.30, alpha: 1),
             lips: UIColor(red: 0.85, green: 0.10, blue: 0.20, alpha: 1), hair2D: .full, browWeight: 0.9,
             browColor: UIColor(red: 0.50, green: 0.18, blue: 0.08, alpha: 1), eyeScale: 1.05, extras: [.eyeshadow, .freckles, .beautyMark, .blush],
             shape: FaceLayout.standardShape(jawWidth: 0.95, chinDrop: 0.0, mouthWidth: 0.2), hat: .none, volume: .bun),
        Spec(id: "00000000-0000-0000-0000-00000000B003", name: "Coach Brick", tagline: "Has never once skipped leg day.",
             skin: UIColor(red: 0.80, green: 0.57, blue: 0.42, alpha: 1), hair: UIColor(red: 0.15, green: 0.11, blue: 0.08, alpha: 1),
             shirt: UIColor(red: 0.80, green: 0.12, blue: 0.12, alpha: 1), iris: UIColor(red: 0.35, green: 0.22, blue: 0.12, alpha: 1),
             lips: UIColor(red: 0.62, green: 0.38, blue: 0.32, alpha: 1), hair2D: .buzz, browWeight: 1.6,
             browColor: UIColor(red: 0.12, green: 0.08, blue: 0.06, alpha: 1), eyeScale: 0.9, extras: [.stubble],
             shape: FaceLayout.standardShape(jawWidth: 1.18, chinDrop: 0.025, mouthWidth: 0.22), hat: .headband, volume: .none),
        Spec(id: "00000000-0000-0000-0000-00000000B004", name: "Baby Benny", tagline: "Small. Loud. Undefeated.",
             skin: UIColor(red: 1.0, green: 0.87, blue: 0.78, alpha: 1), hair: UIColor(red: 0.62, green: 0.45, blue: 0.25, alpha: 1),
             shirt: UIColor(red: 0.35, green: 0.62, blue: 0.95, alpha: 1), iris: UIColor(red: 0.30, green: 0.45, blue: 0.70, alpha: 1),
             lips: UIColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 1), hair2D: .curl, browWeight: 0.5,
             browColor: UIColor(red: 0.70, green: 0.55, blue: 0.40, alpha: 1), eyeScale: 1.3, extras: [.blush],
             shape: FaceLayout.standardShape(jawWidth: 1.12, chinDrop: -0.05, noseLength: -0.02, mouthWidth: 0.13), hat: .partyHat, volume: .none),
        Spec(id: "00000000-0000-0000-0000-00000000B005", name: "Disco Dolores", tagline: "Brought her own spotlight.",
             skin: UIColor(red: 0.45, green: 0.30, blue: 0.21, alpha: 1), hair: UIColor(red: 0.08, green: 0.06, blue: 0.06, alpha: 1),
             shirt: UIColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1), iris: UIColor(red: 0.25, green: 0.15, blue: 0.08, alpha: 1),
             lips: UIColor(red: 0.80, green: 0.10, blue: 0.50, alpha: 1), hair2D: .full, browWeight: 1.0,
             browColor: UIColor(red: 0.08, green: 0.06, blue: 0.06, alpha: 1), eyeScale: 1.05, extras: [.shades],
             shape: FaceLayout.standardShape(jawWidth: 1.0, chinDrop: 0.0, mouthWidth: 0.21), hat: .none, volume: .afro),
        Spec(id: "00000000-0000-0000-0000-00000000B006", name: "Sir Reginald", tagline: "Owns three monocles. Lost two.",
             skin: UIColor(red: 0.96, green: 0.82, blue: 0.74, alpha: 1), hair: UIColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1),
             shirt: UIColor(red: 0.12, green: 0.30, blue: 0.22, alpha: 1), iris: UIColor(red: 0.40, green: 0.40, blue: 0.35, alpha: 1),
             lips: UIColor(red: 0.75, green: 0.50, blue: 0.48, alpha: 1), hair2D: .full, browWeight: 1.2,
             browColor: UIColor(white: 0.35, alpha: 1), eyeScale: 0.95, extras: [.monocle, .curledMustache],
             shape: FaceLayout.standardShape(jawWidth: 0.9, chinDrop: 0.045, noseLength: 0.02, mouthWidth: 0.17), hat: .topHat, volume: .none),
    ]

    static func make() -> [GameCharacter] {
        specs.map { spec in
            let meta = CharacterMeta(id: UUID(uuidString: spec.id)!, name: spec.name, tagline: spec.tagline,
                                     shape: spec.shape, hat: spec.hat, hairVolume: spec.volume, googlyEyes: false,
                                     skinRGB: spec.skin.rgbArray, hairRGB: spec.hair.rgbArray, shirtRGB: spec.shirt.rgbArray,
                                     isDefault: true, createdAt: .distantPast)
            return GameCharacter(meta: meta, texture: paint(spec))
        }
    }

    // MARK: - Face painter

    static func paint(_ spec: Spec) -> UIImage {
        let T = FaceLayout.textureSize
        let shape = spec.shape
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: T, height: T), format: format).image { ctx in
            let c = ctx.cgContext
            func P(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: u * T, y: v * T) }
            func R(_ cu: CGFloat, _ cv: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: (cu - w / 2) * T, y: (cv - h / 2) * T, width: w * T, height: h * T)
            }
            func radial(_ center: CGPoint, _ radius: CGFloat, _ inner: UIColor, _ outer: UIColor) {
                let colors = [inner.cgColor, outer.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
                }
            }
            var rng = SeededRandom(seed: spec.name.unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) })

            // Skin with soft shading toward the edges of the face for depth.
            spec.skin.setFill(); c.fill(CGRect(x: 0, y: 0, width: T, height: T))
            c.saveGState()
            c.scaleBy(x: 1, y: 1.3)
            radial(CGPoint(x: 0.5 * T, y: 0.47 * T / 1.3), 0.40 * T, spec.skin.withAlphaComponent(0), spec.skin.darker(0.82))
            c.restoreGState()

            // Hair.
            let eyeV = shape.eyeLineV
            switch spec.hair2D {
            case .full, .buzz:
                let col = spec.hair2D == .buzz ? spec.hair.withAlphaComponent(0.75) : spec.hair
                col.setFill()
                let hairline = eyeV - (spec.hair2D == .buzz ? 0.17 : 0.19)
                let path = UIBezierPath()
                path.move(to: P(0, 0)); path.addLine(to: P(1, 0)); path.addLine(to: P(1, 0.64))
                path.addLine(to: P(0.80, 0.64)); path.addLine(to: P(0.79, eyeV - 0.02))
                path.addQuadCurve(to: P(0.5, hairline), controlPoint: P(0.77, hairline - 0.01))
                path.addQuadCurve(to: P(0.21, eyeV - 0.02), controlPoint: P(0.23, hairline - 0.01))
                path.addLine(to: P(0.20, 0.64)); path.addLine(to: P(0, 0.64)); path.close()
                path.fill()
                HairStrands.draw(in: c, color: spec.hair, region: path.cgPath, count: spec.hair2D == .buzz ? 1200 : 3000, rng: &rng)
            case .baldTop:
                spec.hair.setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 0.30 * T, width: 0.22 * T, height: 0.34 * T)).fill()
                UIBezierPath(rect: CGRect(x: 0.78 * T, y: 0.30 * T, width: 0.22 * T, height: 0.34 * T)).fill()
                let sides = CGMutablePath()
                sides.addRect(CGRect(x: 0, y: 0.30 * T, width: 0.22 * T, height: 0.34 * T))
                sides.addRect(CGRect(x: 0.78 * T, y: 0.30 * T, width: 0.22 * T, height: 0.34 * T))
                HairStrands.draw(in: c, color: spec.hair, region: sides, count: 900, rng: &rng)
                radial(P(0.44, 0.10), 0.12 * T, UIColor(white: 1, alpha: 0.35), UIColor(white: 1, alpha: 0))   // shiny scalp
            case .curl:
                spec.hair.setStroke()
                let curl = UIBezierPath()
                var a: CGFloat = 0
                curl.move(to: P(0.5, 0.13))
                while a < 4 * .pi {
                    let r = 0.004 + 0.0035 * a
                    curl.addLine(to: P(0.5 + r * cos(a), 0.10 + r * sin(a)))
                    a += 0.15
                }
                curl.lineWidth = 9; curl.lineCapStyle = .round; curl.stroke()
            }

            // Cheeks.
            if spec.extras.contains(.blush) {
                for u in [shape.leftEye.x - 0.02, shape.rightEye.x + 0.02] {
                    radial(P(u, eyeV + 0.14), 0.06 * T, UIColor(red: 1, green: 0.35, blue: 0.40, alpha: 0.45), UIColor(red: 1, green: 0.35, blue: 0.4, alpha: 0))
                }
            }
            if spec.extras.contains(.freckles) {
                UIColor(red: 0.62, green: 0.38, blue: 0.25, alpha: 0.55).setFill()
                for _ in 0..<38 {
                    let side: CGFloat = rng.next() < 0.5 ? -1 : 1
                    let u = 0.5 + side * (0.05 + rng.next() * 0.11), v = eyeV + 0.07 + rng.next() * 0.08
                    UIBezierPath(ovalIn: R(u, v, 0.006, 0.006)).fill()
                }
            }
            if spec.extras.contains(.stubble) {
                UIColor(red: 0.12, green: 0.08, blue: 0.06, alpha: 0.28).setFill()
                for _ in 0..<1500 {
                    let a = rng.next() * .pi, r = 0.62 + rng.next() * 0.38
                    let u = 0.5 + cos(a) * 0.27 * r
                    let v = shape.mouthCenter.y - 0.06 + sin(a) * (shape.chin.y - shape.mouthCenter.y + 0.06) * r
                    if abs(u - shape.mouthCenter.x) < shape.mouthWidth * 0.55 && abs(v - shape.mouthCenter.y) < 0.03 { continue }
                    UIBezierPath(ovalIn: R(u, v, 0.0035, 0.0035)).fill()
                }
            }

            // Eyes.
            for eye in [shape.leftEye, shape.rightEye] {
                let s = spec.eyeScale
                if spec.extras.contains(.eyeshadow) {
                    radial(P(eye.x, eye.y - 0.018), 0.05 * T, UIColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 0.75), UIColor(red: 0.3, green: 0.55, blue: 0.95, alpha: 0))
                }
                UIColor.white.setFill()
                UIBezierPath(ovalIn: R(eye.x, eye.y, 0.075 * s, 0.038 * s)).fill()
                spec.iris.setFill()
                UIBezierPath(ovalIn: R(eye.x, eye.y, 0.032 * s, 0.032 * s)).fill()
                UIColor.black.setFill()
                UIBezierPath(ovalIn: R(eye.x, eye.y, 0.014 * s, 0.014 * s)).fill()
                UIColor(white: 1, alpha: 0.9).setFill()
                UIBezierPath(ovalIn: R(eye.x + 0.007 * s, eye.y - 0.007 * s, 0.008 * s, 0.008 * s)).fill()
                // Upper lid.
                let lid = UIBezierPath()
                lid.move(to: P(eye.x - 0.039 * s, eye.y + 0.002))
                lid.addQuadCurve(to: P(eye.x + 0.039 * s, eye.y + 0.002), controlPoint: P(eye.x, eye.y - 0.034 * s))
                lid.lineWidth = 5; spec.skin.darker(0.45).setStroke(); lid.stroke()
                // Brow.
                spec.browColor.setFill()
                let bw = 0.09 * (0.8 + 0.2 * spec.browWeight), bh = 0.012 * spec.browWeight
                let outer: CGFloat = eye.x < 0.5 ? -1 : 1
                c.saveGState()
                c.translateBy(x: eye.x * T, y: (eye.y - 0.06) * T)
                c.rotate(by: outer * 0.10)
                UIBezierPath(roundedRect: CGRect(x: -bw / 2 * T, y: -bh / 2 * T, width: bw * T, height: bh * T), cornerRadius: bh * T / 2).fill()
                c.restoreGState()
            }

            // Nose: nostrils and a soft shadow under the tip.
            let n = shape.noseTip
            radial(P(n.x, n.y + 0.012), 0.04 * T, spec.skin.darker(0.75).withAlphaComponent(0.6), spec.skin.withAlphaComponent(0))
            spec.skin.darker(0.45).setFill()
            UIBezierPath(ovalIn: R(n.x - 0.02, n.y + 0.01, 0.016, 0.009)).fill()
            UIBezierPath(ovalIn: R(n.x + 0.02, n.y + 0.01, 0.016, 0.009)).fill()

            // Mouth: two lips and a slight smile.
            let m = shape.mouthCenter, mw = shape.mouthWidth
            spec.lips.setFill()
            UIBezierPath(ovalIn: R(m.x, m.y + 0.009, mw * 0.80, 0.030)).fill()
            spec.lips.darker(0.85).setFill()
            UIBezierPath(ovalIn: R(m.x, m.y - 0.006, mw * 0.85, 0.022)).fill()
            let smile = UIBezierPath()
            smile.move(to: P(m.x - mw / 2, m.y - 0.006))
            smile.addQuadCurve(to: P(m.x + mw / 2, m.y - 0.006), controlPoint: P(m.x, m.y + 0.018))
            smile.lineWidth = 5; smile.lineCapStyle = .round; spec.lips.darker(0.4).setStroke(); smile.stroke()

            if spec.extras.contains(.beautyMark) {
                UIColor(red: 0.2, green: 0.1, blue: 0.08, alpha: 1).setFill()
                UIBezierPath(ovalIn: R(m.x + mw * 0.6, m.y - 0.03, 0.009, 0.009)).fill()
            }

            // Facial hair.
            if spec.extras.contains(.walrusMustache) {
                spec.hair.setFill()
                for side: CGFloat in [-1, 1] {
                    UIBezierPath(ovalIn: R(n.x + side * 0.045, n.y + 0.045, 0.11, 0.05)).fill()
                }
                UIBezierPath(ovalIn: R(n.x, n.y + 0.038, 0.06, 0.04)).fill()
            }
            if spec.extras.contains(.curledMustache) {
                spec.hair.darker(0.6).setStroke()
                for side: CGFloat in [-1, 1] {
                    let p = UIBezierPath()
                    p.move(to: P(n.x, n.y + 0.035))
                    p.addCurve(to: P(n.x + side * 0.10, n.y + 0.02),
                               controlPoint1: P(n.x + side * 0.04, n.y + 0.06),
                               controlPoint2: P(n.x + side * 0.09, n.y + 0.06))
                    p.addQuadCurve(to: P(n.x + side * 0.085, n.y + 0.0), controlPoint: P(n.x + side * 0.115, n.y - 0.005))
                    p.lineWidth = 13; p.lineCapStyle = .round; p.stroke()
                }
            }

            // Eyewear.
            if spec.extras.contains(.glasses) {
                UIColor(white: 0.1, alpha: 1).setStroke()
                for eye in [shape.leftEye, shape.rightEye] {
                    let g = UIBezierPath(ovalIn: R(eye.x, eye.y + 0.004, 0.11, 0.085)); g.lineWidth = 9; g.stroke()
                }
                let bridge = UIBezierPath()
                bridge.move(to: P(shape.leftEye.x + 0.055, shape.leftEye.y))
                bridge.addQuadCurve(to: P(shape.rightEye.x - 0.055, shape.rightEye.y), controlPoint: P(0.5, eyeV - 0.02))
                bridge.lineWidth = 8; bridge.stroke()
            }
            if spec.extras.contains(.monocle) {
                let e = shape.rightEye
                UIColor(red: 0.85, green: 0.68, blue: 0.20, alpha: 1).setStroke()
                let ring = UIBezierPath(ovalIn: R(e.x, e.y, 0.10, 0.10)); ring.lineWidth = 8; ring.stroke()
                let chain = UIBezierPath()
                chain.move(to: P(e.x + 0.03, e.y + 0.05))
                chain.addQuadCurve(to: P(0.78, 0.70), controlPoint: P(e.x + 0.02, 0.68))
                chain.lineWidth = 4; chain.setLineDash([10, 6], count: 2, phase: 0); chain.stroke()
                UIColor(white: 1, alpha: 0.18).setFill()
                UIBezierPath(ovalIn: R(e.x, e.y, 0.095, 0.095)).fill()
            }
            if spec.extras.contains(.shades) {
                for eye in [shape.leftEye, shape.rightEye] {
                    UIColor(red: 0.95, green: 0.25, blue: 0.55, alpha: 0.92).setFill()
                    UIBezierPath(roundedRect: R(eye.x, eye.y + 0.005, 0.12, 0.075), cornerRadius: 0.03 * T).fill()
                    UIColor(white: 1, alpha: 0.5).setFill()
                    UIBezierPath(ovalIn: R(eye.x - 0.025, eye.y - 0.012, 0.025, 0.012)).fill()
                }
                UIColor(red: 0.85, green: 0.70, blue: 0.20, alpha: 1).setStroke()
                let bridge = UIBezierPath()
                bridge.move(to: P(shape.leftEye.x + 0.06, eyeV)); bridge.addLine(to: P(shape.rightEye.x - 0.06, eyeV))
                bridge.lineWidth = 7; bridge.stroke()
            }
        }
    }
}

/// Tiny deterministic RNG so default faces look the same every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 1_000_000) / 1_000_000
    }
}
