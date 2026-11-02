import SceneKit
import UIKit
import CoreImage

/// Caches sculpted meshes so each character is only sculpted once per launch.
enum HeadGeometryCache {
    private static var cache: [UUID: (FaceShape, HeadMeshBuilder.Output)] = [:]
    private static let lock = NSLock()

    static func output(for character: GameCharacter) -> HeadMeshBuilder.Output {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[character.id], hit.0 == character.meta.shape { return hit.1 }
        let out = HeadMeshBuilder.build(shape: character.meta.shape)
        cache[character.id] = (character.meta.shape, out)
        return out
    }
}

/// A living big head: mesh + blend shapes + accessories + reactions.
///
/// Node hierarchy (pivot at the neck so wobbles look like a bobblehead):
///   root ─ idle ─ wobble ─ head (mesh, morpher) ─ splats / accessories
final class HeadRig {
    static let neckOffset: Float = 1.2
    /// Dry skin: soft sheen only. Photos already carry their own shine, and more on top read as
    /// a white, sweaty forehead.
    static let dryRoughness: CGFloat = 0.68
    static let dryClearCoat: CGFloat = 0.02
    /// Skin sheen on the face; matte where every texture puts hair (crown, sides, back) so the
    /// back of the head reads as hair rather than a shiny grey cap.
    static let dryRoughnessMap: UIImage = {
        let T: CGFloat = 256
        let img = UIGraphicsImageRenderer(size: CGSize(width: T, height: T)).image { ctx in
            UIColor(white: dryRoughness, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: T, height: T))
            UIColor(white: 0.97, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: T, height: 0.14 * T))
            ctx.fill(CGRect(x: 0, y: 0, width: 0.17 * T, height: 0.62 * T))
            ctx.fill(CGRect(x: 0.83 * T, y: 0, width: 0.17 * T, height: 0.62 * T))
        }
        let blurred = CIImage(image: img)!.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 8])
            .cropped(to: CGRect(x: 0, y: 0, width: T, height: T))
        return CIContext().createCGImage(blurred, from: blurred.extent).map { UIImage(cgImage: $0) } ?? img
    }()

    let character: GameCharacter
    let root = SCNNode()
    let idle = SCNNode()
    let wobble = SCNNode()
    let head = SCNNode()
    let splats = SCNNode()
    let anchors: HeadMeshBuilder.Output

    init(character: GameCharacter) {
        self.character = character
        anchors = HeadGeometryCache.output(for: character)

        let geometry = anchors.geometry.copy() as! SCNGeometry
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = character.texture
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 16   // keeps the photo sharp where the face curves away
        material.roughness.contents = HeadRig.dryRoughnessMap
        material.metalness.contents = 0.0
        // Fine pore detail and a faint skin sheen.
        material.normal.contents = Effects.skinNormalMap
        material.normal.intensity = 0.3
        material.normal.wrapS = .repeat
        material.normal.wrapT = .repeat
        material.normal.contentsTransform = SCNMatrix4MakeScale(9, 9, 1)
        material.clearCoat.contents = HeadRig.dryClearCoat
        material.clearCoatRoughness.contents = 0.5
        geometry.materials = [material]
        head.geometry = geometry

        let morpher = SCNMorpher()
        morpher.targets = anchors.morphTargets
        // Targets are full meshes: result = base + Σ wᵢ·(targetᵢ − base).
        morpher.calculationMode = .normalized
        head.morpher = morpher

        head.position = SCNVector3(0, HeadRig.neckOffset, 0)
        root.name = "head-\(character.name)"
        root.addChildNode(idle)
        idle.addChildNode(wobble)
        wobble.addChildNode(head)
        head.addChildNode(splats)
        Accessories.attach(to: self)
    }

    /// World-space center of the face (roughly the nose), for aiming pies and punches.
    var faceWorldPosition: SCNVector3 {
        head.convertPosition(SCNVector3(0, anchors.eyeY - 0.25, 1.1), to: nil)
    }

    // MARK: - Expressions

    func setMorph(_ morph: Morph, _ weight: CGFloat) {
        setWeight(weight, morph.rawValue)
    }

    /// Sets an expression on the face and on any cream stuck to it.
    private func setWeight(_ weight: CGFloat, _ name: String) {
        head.morpher?.setWeight(weight, forTargetNamed: name)
        coat?.node.morpher?.setWeight(weight, forTargetNamed: name)
    }

    /// Snap into an expression, hold, then jiggle back with an elastic overshoot.
    func pulse(_ morph: Morph, peak: CGFloat = 1, attack: TimeInterval = 0.05, hold: TimeInterval = 0.12, release: TimeInterval = 0.7) {
        let name = morph.rawValue
        let up = SCNAction.customAction(duration: attack) { [weak self] _, t in
            self?.setWeight(peak * min(1, t / CGFloat(max(attack, 0.001))), name)
        }
        let wait = SCNAction.wait(duration: hold)
        let down = SCNAction.customAction(duration: release) { [weak self] _, t in
            let p = Double(t) / max(release, 0.001)
            let w = peak * CGFloat(exp(-4 * p) * cos(3 * .pi * p))
            self?.setWeight(max(w, -0.35), name)
        }
        let reset = SCNAction.run { [weak self] _ in self?.setWeight(0, name) }
        head.runAction(.sequence([up, wait, down, reset]), forKey: "morph-\(name)")
    }

    /// Hold an expression (e.g. mouth open while a pie flies in).
    func hold(_ morph: Morph, weight: CGFloat, duration: TimeInterval = 0.25) {
        let name = morph.rawValue
        let start = head.morpher?.weight(forTargetNamed: name) ?? 0
        head.runAction(.customAction(duration: duration) { [weak self] _, t in
            let p = t / CGFloat(max(duration, 0.001))
            self?.setWeight(start + (weight - start) * p, name)
        }, forKey: "morph-\(name)")
    }

    // MARK: - Bobblehead physics

    /// Damped spring wobble around the neck. `sideways` tilts left/right, `back` nods backwards.
    func wobbleHit(sideways: Float, back: Float, strength: Float = 1) {
        let freq = 2.4
        wobble.removeAction(forKey: "wobble")
        wobble.runAction(.customAction(duration: 1.6) { node, t in
            let time = Double(t)
            let amp = Float(exp(-3.2 * time) * sin(2 * .pi * freq * time + 0.35)) * strength
            node.eulerAngles = SCNVector3(-back * 0.55 * amp, 0, -sideways * 0.65 * amp)
        }, forKey: "wobble")
    }

    func startIdle(seed: Double = 0) {
        idle.runAction(.repeatForever(.customAction(duration: 6.283) { node, t in
            let time = Double(t) + seed
            node.eulerAngles = SCNVector3(Float(sin(time * 1.3)) * 0.03, Float(sin(time * 0.7)) * 0.10, Float(sin(time)) * 0.04)
        }), forKey: "idle")
    }

    func spinOut() {
        wobble.runAction(.sequence([
            .rotateBy(x: 0, y: CGFloat.pi * 6, z: 0, duration: 1.4),
            .rotateTo(x: 0.4, y: 0, z: 0.9, duration: 0.3, usesShortestUnitArc: true),
        ]), forKey: "wobble")
    }

    // MARK: - Cream

    /// The cream on this face, built on the first pie.
    private var coat: CreamCoat?
    /// Dollops and crumbs stuck in the cream, one node per pie, oldest first.
    private var creamBits: [SCNNode] = []

    /// The pie lands: cream spreads over the face and piles onto what's already there, runs drip
    /// down from it, and whipped dollops and crust crumbs stick in it. The first pie hits the
    /// middle; later ones land all over, so a few throws cover the whole face.
    func splatCream(amount: Int = 22) {
        prepareCream()
        guard let coat else { return }
        // The first pie hits the middle of the face; later ones land all over it.
        let center = coat.splats == 0
            ? SIMD2(Float.random(in: -0.1...0.1), anchors.eyeY - 0.35)
            : SIMD2(Float.random(in: -0.65...0.65), Float.random(in: (anchors.chinY + 0.25)...(anchors.foreheadY + 0.1)))
        let radius = Float.random(in: 0.78...0.92) + Float(min(amount, 30) - 22) * 0.012
        let spots = coat.splat(center: center, radius: radius, seed: Float.random(in: 0...50))

        // Whipped dollops half-sunk in the cream, and crust crumbs.
        let mess = SCNNode()
        for k in 0..<(spots.isEmpty ? 0 : 7) {
            let isCrumb = k >= 2
            let (p, n) = spots.randomElement()!
            let holder = SCNNode()
            holder.simdPosition = p + n * (isCrumb ? 0.01 : -0.01)
            holder.simdLook(at: holder.simdPosition + n, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 1, 0))
            let piece = SCNNode(geometry: isCrumb ? Cream.crumbs.randomElement()! : Cream.dollops.randomElement()!)
            let size = isCrumb ? Float.random(in: 0.02...0.045) : Float.random(in: 0.1...0.14)
            piece.scale = SCNVector3(size, size * (isCrumb ? 0.6 : Float.random(in: 0.3...0.4)), size)
            piece.eulerAngles.y = Float.random(in: 0...(2 * .pi))
            holder.addChildNode(piece)
            mess.addChildNode(holder)
        }
        // The new bits land with a splat: squashed flat, then settle.
        mess.scale = SCNVector3(1.1, 1.1, 0.3)
        mess.runAction(.customAction(duration: 0.14) { node, t in
            let p = Float(t / 0.14)
            node.scale = SCNVector3(1.1 - 0.1 * p, 1.1 - 0.1 * p, 0.3 + 0.7 * p)
        })
        splats.addChildNode(mess)
        creamBits.append(mess)
        // Keep the pile from growing forever: the oldest bits are buried under new cream anyway.
        while creamBits.count > 8 { creamBits.removeFirst().removeFromParentNode() }
    }

    func clearCream() {
        creamBits.forEach { $0.removeFromParentNode() }
        creamBits = []
        coat?.reset()
    }

    /// Builds the (still hidden) cream before the first pie, so nothing is built or compiled
    /// mid-throw: the coat, plus a pie, dollop and crumb tucked inside the head where they're
    /// never seen but their materials are ready.
    func prepareCream() {
        guard coat == nil, let c = CreamCoat(head: anchors.geometry, targets: anchors.morphTargets, cols: HeadMeshBuilder.segments + 1) else { return }
        coat = c
        splats.addChildNode(c.node)
        let warm = SCNNode()
        warm.name = "creamWarmUp"
        warm.position = SCNVector3(0, anchors.eyeY - 0.3, 0)
        warm.scale = SCNVector3(0.05, 0.05, 0.05)
        warm.addChildNode(SCNNode(geometry: Cream.dollops[0]))
        warm.addChildNode(SCNNode(geometry: Cream.crumbs[0]))
        warm.addChildNode(Effects.makePie())
        warm.enumerateHierarchy { n, _ in n.castsShadow = false }
        splats.addChildNode(warm)
    }

    var creamLevel: Int { splats.childNodes.count }

    // MARK: - Looks

    /// Soaked: glossy, a little darker, dripping for a few seconds.
    func setWet(_ wet: Bool, in scene: SCNScene? = nil) {
        guard let m = head.geometry?.firstMaterial else { return }
        m.roughness.contents = wet ? 0.18 : HeadRig.dryRoughnessMap
        m.clearCoat.contents = wet ? 0.9 : HeadRig.dryClearCoat
        m.clearCoatRoughness.contents = wet ? 0.08 : 0.5
        m.multiply.contents = wet ? UIColor(white: 0.84, alpha: 1) : UIColor.white
        guard wet, let scene else { return }
        let chin = SCNVector3(0, anchors.chinY + 0.05, 0.6)
        head.runAction(.repeat(.sequence([
            .run { [weak self] node in
                guard let self else { return }
                let p = node.convertPosition(SCNVector3(chin.x + Float.random(in: -0.3...0.3), chin.y, chin.z), to: nil)
                DispatchQueue.main.async {
                    Effects.burst(in: scene, at: p, color: UIColor(red: 0.62, green: 0.85, blue: 1, alpha: 1), count: 3, velocity: 0.4,
                                  size: CGFloat(0.02 + 0.05 * self.root.scale.x), direction: SCNVector3(0, -1, 0), spread: 20, lifespan: 0.8)
                }
            },
            .wait(duration: 0.22),
        ]), count: 18), forKey: "drip")
    }

    /// Golden glow for bonus targets.
    func setGolden(_ golden: Bool) {
        head.geometry?.firstMaterial?.emission.contents = golden ? UIColor(red: 0.48, green: 0.33, blue: 0, alpha: 1) : UIColor.black
    }
}
