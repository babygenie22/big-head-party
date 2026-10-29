import SceneKit
import UIKit

/// Shared visual effects: cream, pies, particles, lights and camera shake.
enum Effects {
    static let creamMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 1.0, green: 0.98, blue: 0.93, alpha: 1)
        m.roughness.contents = 0.3
        m.metalness.contents = 0
        return m
    }()

    /// Tileable skin-pore normal map (generated once).
    static let skinNormalMap: UIImage = makeSkinNormalMap()

    private static func toByte(_ v: Float) -> UInt8 {
        let scaled: Float = (v * 0.5 + 0.5) * 255
        return UInt8(max(0, min(255, scaled)))
    }

    private static func makeSkinNormalMap() -> UIImage {
        let n = 256
        let count = n * n
        var rng = SeededRandom(seed: 99)
        var h = [Float](repeating: 0, count: count)
        for i in 0..<count { h[i] = Float(rng.next()) }
        for _ in 0..<2 {
            var next = h
            for i in 0..<count {
                let sum: Float = h[i] * 2 + h[(i + 1) % count] + h[(i + n) % count]
                next[i] = sum / 4
            }
            h = next
        }
        var px = [UInt8](repeating: 255, count: count * 4)
        for y in 0..<n {
            for x in 0..<n {
                let right: Float = h[y * n + (x + 1) % n], left: Float = h[y * n + (x + n - 1) % n]
                let down: Float = h[((y + 1) % n) * n + x], up: Float = h[((y + n - 1) % n) * n + x]
                let dx: Float = (right - left) * 4
                let dy: Float = (down - up) * 4
                let l: Float = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * n + x) * 4
                px[i] = toByte(-dx / l)
                px[i + 1] = toByte(-dy / l)
                px[i + 2] = toByte(1 / l)
            }
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: cg)
    }

    /// Vertical carnival stripes.
    static func stripes(_ a: UIColor, _ b: UIColor, count: Int = 16) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256)).image { ctx in
            for i in 0..<count {
                (i % 2 == 0 ? a : b).setFill()
                ctx.fill(CGRect(x: CGFloat(i) * 512 / CGFloat(count), y: 0, width: 512 / CGFloat(count) + 1, height: 256))
            }
        }
    }

    /// Show title painted on a banner.
    static func banner(_ text: String, background: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 256)).image { ctx in
            background.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 256))
            let font = UIFont.systemFont(ofSize: 130, weight: .black)
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let shadow: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(red: 0.93, green: 0.23, blue: 0.34, alpha: 1), .paragraphStyle: style]
            let main: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(red: 1, green: 0.81, blue: 0.29, alpha: 1), .paragraphStyle: style]
            (text as NSString).draw(in: CGRect(x: 6, y: 50, width: 1024, height: 180), withAttributes: shadow)
            (text as NSString).draw(in: CGRect(x: 0, y: 44, width: 1024, height: 180), withAttributes: main)
        }
    }

    static let dotImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.55, 1])!
        ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                         endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }

    static let starImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { _ in
        let star = UIBezierPath()
        for i in 0..<10 {
            let r: CGFloat = i % 2 == 0 ? 30 : 12
            let a = CGFloat(i) * .pi / 5 - .pi / 2
            let p = CGPoint(x: 32 + r * cos(a), y: 32 + r * sin(a))
            i == 0 ? star.move(to: p) : star.addLine(to: p)
        }
        star.close()
        UIColor.white.setFill()
        star.fill()
    }

    /// One-shot particle burst in world space.
    static func burst(in scene: SCNScene, at position: SCNVector3, color: UIColor, count: CGFloat = 80,
                      velocity: CGFloat = 4, size: CGFloat = 0.07, image: UIImage = dotImage,
                      direction: SCNVector3 = SCNVector3(0, 0, 1), spread: CGFloat = 75, gravity: Bool = true,
                      lifespan: CGFloat = 0.9) {
        let ps = SCNParticleSystem()
        ps.loops = false
        ps.emissionDuration = 0.06
        ps.birthRate = count / 0.06
        ps.particleLifeSpan = lifespan
        ps.particleLifeSpanVariation = lifespan * 0.35
        ps.particleVelocity = velocity
        ps.particleVelocityVariation = velocity * 0.6
        ps.emittingDirection = direction
        ps.spreadingAngle = spread
        ps.particleSize = size
        ps.particleSizeVariation = size * 0.6
        ps.particleColor = color
        ps.particleImage = image
        ps.particleAngularVelocity = 180
        ps.particleAngularVelocityVariation = 360
        ps.acceleration = gravity ? SCNVector3(0, -9.8, 0) : SCNVector3(0, 0, 0)
        ps.blendMode = .alpha
        ps.isLightingEnabled = false
        let fade = CAKeyframeAnimation()
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.7, 1]
        ps.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        scene.addParticleSystem(ps, transform: SCNMatrix4MakeTranslation(position.x, position.y, position.z))
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(lifespan) * 2 + 0.5) {
            scene.removeParticleSystem(ps)
        }
    }

    static func confetti(in scene: SCNScene, at position: SCNVector3) {
        for color in [UIColor.systemPink, .systemYellow, .systemTeal, .systemPurple, .systemGreen] {
            burst(in: scene, at: position, color: color, count: 40, velocity: 6, size: 0.09,
                  direction: SCNVector3(0, 1, 0.3), spread: 50, lifespan: 2.2)
        }
    }

    /// A cream pie with a cherry. The returned node's local +Z is the cream side.
    static func makePie() -> SCNNode {
        let container = SCNNode()
        container.name = "pie"
        let pie = SCNNode()
        pie.eulerAngles.x = .pi / 2   // cream (+Y) → +Z
        container.addChildNode(pie)
        let tinMat = Accessories.material(UIColor(white: 0.8, alpha: 1), roughness: 0.25, metalness: 1)
        pie.addChildNode(Accessories.node(SCNCylinder(radius: 0.55, height: 0.14), tinMat, at: SCNVector3(0, 0, 0)))
        pie.addChildNode(Accessories.node(SCNTorus(ringRadius: 0.5, pipeRadius: 0.08),
                                          Accessories.material(UIColor(red: 0.85, green: 0.6, blue: 0.3, alpha: 1), roughness: 0.8),
                                          at: SCNVector3(0, 0.08, 0)))
        let cream = SCNNode(geometry: SCNSphere(radius: 0.5))
        cream.geometry?.materials = [creamMaterial]
        cream.position = SCNVector3(0, 0.1, 0)
        cream.scale = SCNVector3(1, 0.45, 1)
        pie.addChildNode(cream)
        pie.addChildNode(Accessories.node(SCNSphere(radius: 0.09), Accessories.material(.systemRed, roughness: 0.15),
                                          at: SCNVector3(0, 0.34, 0)))
        return container
    }

    /// Shakes a camera node in its local space, decaying over `duration`.
    static func shake(_ camera: SCNNode, intensity: Float = 0.12, duration: TimeInterval = 0.4) {
        let base = camera.position
        camera.removeAction(forKey: "shake")
        camera.runAction(.sequence([
            .customAction(duration: duration) { node, t in
                let k = intensity * Float(1 - Double(t) / duration)
                node.position = SCNVector3(base.x + Float.random(in: -k...k), base.y + Float.random(in: -k...k), base.z)
            },
            .move(to: base, duration: 0.05),
        ]), forKey: "shake")
    }

    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .heavy) {
        DispatchQueue.main.async { UIImpactFeedbackGenerator(style: style).impactOccurred() }
    }

    // MARK: - Lighting

    /// Soft studio lighting + a gradient environment so PBR skin doesn't look like plastic.
    static func addStudioLights(to scene: SCNScene, rim: UIColor = .systemPink, fill: UIColor = UIColor(red: 0.6, green: 0.75, blue: 1, alpha: 1)) {
        let env = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256)).image { ctx in
            let colors = [UIColor(white: 0.95, alpha: 1).cgColor, UIColor(red: 0.55, green: 0.5, blue: 0.6, alpha: 1).cgColor,
                          UIColor(white: 0.12, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
        scene.lightingEnvironment.contents = env
        scene.lightingEnvironment.intensity = 0.8

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 250
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1100
        key.light?.color = UIColor(red: 1, green: 0.96, blue: 0.9, alpha: 1)
        key.light?.castsShadow = true
        key.light?.shadowRadius = 6
        key.light?.shadowSampleCount = 8
        key.light?.shadowColor = UIColor(white: 0, alpha: 0.35)
        key.eulerAngles = SCNVector3(-0.65, 0.45, 0)
        scene.rootNode.addChildNode(key)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .omni
        fillLight.light?.intensity = 450
        fillLight.light?.color = fill
        fillLight.position = SCNVector3(-5, 3, 6)
        scene.rootNode.addChildNode(fillLight)

        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .omni
        rimLight.light?.intensity = 900
        rimLight.light?.color = rim
        rimLight.position = SCNVector3(3, 5, -5)
        scene.rootNode.addChildNode(rimLight)
    }

    /// `horizontal: true` fixes the field of view across the screen's width, so wide scenes
    /// (two contestants, a tank and a target) always fit a tall phone screen.
    static func makeCamera(fov: CGFloat = 40, horizontal: Bool = false) -> SCNNode {
        let camera = SCNCamera()
        camera.projectionDirection = horizontal ? .horizontal : .vertical
        camera.fieldOfView = fov
        camera.zNear = 0.1
        camera.zFar = 100
        camera.wantsHDR = true
        camera.exposureOffset = -0.25
        camera.bloomIntensity = 0.2
        camera.bloomThreshold = 0.95
        camera.vignettingIntensity = 0.4
        let node = SCNNode()
        node.camera = camera
        return node
    }
}
