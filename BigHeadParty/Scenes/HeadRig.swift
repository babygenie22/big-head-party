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
        head.morpher?.setWeight(weight, forTargetNamed: morph.rawValue)
    }

    /// Snap into an expression, hold, then jiggle back with an elastic overshoot.
    func pulse(_ morph: Morph, peak: CGFloat = 1, attack: TimeInterval = 0.05, hold: TimeInterval = 0.12, release: TimeInterval = 0.7) {
        let name = morph.rawValue
        let up = SCNAction.customAction(duration: attack) { node, t in
            node.morpher?.setWeight(peak * min(1, t / CGFloat(max(attack, 0.001))), forTargetNamed: name)
        }
        let wait = SCNAction.wait(duration: hold)
        let down = SCNAction.customAction(duration: release) { node, t in
            let p = Double(t) / max(release, 0.001)
            let w = peak * CGFloat(exp(-4 * p) * cos(3 * .pi * p))
            node.morpher?.setWeight(max(w, -0.35), forTargetNamed: name)
        }
        let reset = SCNAction.run { node in node.morpher?.setWeight(0, forTargetNamed: name) }
        head.runAction(.sequence([up, wait, down, reset]), forKey: "morph-\(name)")
    }

    /// Hold an expression (e.g. mouth open while a pie flies in).
    func hold(_ morph: Morph, weight: CGFloat, duration: TimeInterval = 0.25) {
        let name = morph.rawValue
        let start = head.morpher?.weight(forTargetNamed: name) ?? 0
        head.runAction(.customAction(duration: duration) { node, t in
            let p = t / CGFloat(max(duration, 0.001))
            node.morpher?.setWeight(start + (weight - start) * p, forTargetNamed: name)
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

    /// The pie lands: a cream layer molded to this person's actual face, whipped dollops and
    /// crust crumbs stuck in it, and drips that run down the chin. `amount` scales the mess.
    func splatCream(amount: Int = 22) {
        let mess = SCNNode()
        let cx = Float.random(in: -0.15...0.15)
        let cy = (anchors.chinY + anchors.foreheadY) / 2 + Float.random(in: -0.1...0.1)
        let radius = 0.55 + Float(min(amount, 30)) * 0.012
        if let layer = Cream.layer(on: head, center: SIMD2(cx, cy), radius: radius, seed: Float.random(in: 0...50)) {
            mess.addChildNode(layer)
        }
        // Dollops and crumbs, raycast onto the face so they sit in the cream.
        let dollopCount = max(3, amount / 5), crumbCount = max(4, amount / 4)
        var placed = 0, tries = 0
        while placed < dollopCount + crumbCount && tries < (dollopCount + crumbCount) * 4 {
            tries += 1
            let a = Float.random(in: 0...(2 * .pi)), r = radius * 0.6 * sqrt(Float.random(in: 0...1))
            let x = cx + cos(a) * r, y = cy + sin(a) * r
            guard let hit = head.frontSurface(x: x, y: y) else { continue }
            let p = hit.point, n = hit.normal
            let holder = SCNNode()
            holder.position = SCNVector3(p.x + n.x * 0.05, p.y + n.y * 0.05, p.z + n.z * 0.05)
            holder.look(at: SCNVector3(holder.position.x + n.x, holder.position.y + n.y, holder.position.z + n.z),
                        up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
            let isCrumb = placed >= dollopCount
            let piece = SCNNode(geometry: isCrumb ? Cream.crumbs.randomElement()! : Cream.dollops.randomElement()!)
            let size = isCrumb ? Float.random(in: 0.025...0.05) : Float.random(in: 0.1...0.17)
            piece.scale = SCNVector3(size, size * (isCrumb ? 0.6 : Float.random(in: 0.5...0.7)), size)
            piece.eulerAngles.y = Float.random(in: 0...(2 * .pi))
            holder.addChildNode(piece)
            mess.addChildNode(holder)
            placed += 1
        }
        // Drips run down from the bottom edge.
        for _ in 0..<Int.random(in: 2...4) {
            let x = cx + Float.random(in: -radius * 0.5...radius * 0.5), y = cy - radius * Float.random(in: 0.3...0.5)
            guard let hit = head.frontSurface(x: x, y: y) else { continue }
            let drip = Cream.drip()
            drip.position = SCNVector3(hit.point.x, hit.point.y, hit.point.z + 0.03)
            drip.scale = SCNVector3(1, 0.05, 1)
            let length = CGFloat.random(in: 0.35...0.8)
            drip.runAction(.sequence([.wait(duration: .random(in: 0.2...0.6)),
                                      .group([.customAction(duration: 1.8) { node, t in
                                                  node.scale.y = 0.05 + Float(length - 0.05) * Float(t / 1.8)
                                              },
                                              .moveBy(x: 0, y: -0.12, z: 0, duration: 1.8)])]))
            mess.addChildNode(drip)
        }
        // It lands with a splat: squashed flat, then settles.
        mess.scale = SCNVector3(1.15, 1.15, 0.3)
        mess.runAction(.customAction(duration: 0.14) { node, t in
            let p = Float(t / 0.14)
            node.scale = SCNVector3(1.15 - 0.15 * p, 1.15 - 0.15 * p, 0.3 + 0.7 * p)
        })
        splats.addChildNode(mess)
    }

    func clearCream() {
        splats.childNodes.forEach { $0.removeFromParentNode() }
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
