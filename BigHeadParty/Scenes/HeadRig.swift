import SceneKit
import UIKit

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
        material.roughness.contents = 0.55
        material.metalness.contents = 0.0
        // Fine pore detail and a faint skin sheen.
        material.normal.contents = Effects.skinNormalMap
        material.normal.intensity = 0.3
        material.normal.wrapS = .repeat
        material.normal.wrapT = .repeat
        material.normal.contentsTransform = SCNMatrix4MakeScale(9, 9, 1)
        material.clearCoat.contents = 0.05
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

    /// Raycasts onto the real mesh so the cream hugs this person's actual face shape.
    func splatCream(amount: Int = 22) {
        let creamMaterial = Effects.creamMaterial
        var placed = 0
        for _ in 0..<(amount * 3) where placed < amount {
            let x = Float.random(in: -0.75...0.75)
            let y = Float.random(in: (anchors.chinY + 0.15)...(anchors.foreheadY + 0.15))
            let hits = head.hitTestWithSegment(from: SCNVector3(x, y, 3), to: SCNVector3(x, y, -0.5), options: nil)
            guard let hit = hits.first(where: { $0.node === head }) else { continue }
            let p = hit.localCoordinates, n = hit.localNormal
            // Orient a holder along the surface normal, then flatten the blob along it.
            let holder = SCNNode()
            holder.position = p
            holder.look(at: SCNVector3(p.x + n.x, p.y + n.y, p.z + n.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
            let blob = SCNNode(geometry: SCNSphere(radius: CGFloat.random(in: 0.1...0.2)))
            blob.geometry?.materials = [creamMaterial]
            blob.scale = SCNVector3(1, 1, 0.32)
            holder.addChildNode(blob)
            holder.scale = SCNVector3(0.01, 0.01, 0.01)
            holder.runAction(.scale(to: 1, duration: 0.08))
            splats.addChildNode(holder)
            placed += 1

            // A few drips slide down from the lower blobs.
            if y < anchors.eyeY - 0.4 && Bool.random() {
                let drip = SCNNode(geometry: SCNCapsule(capRadius: 0.05, height: 0.3))
                drip.geometry?.materials = [creamMaterial]
                drip.position = SCNVector3(p.x, p.y - 0.05, p.z + 0.02)
                drip.scale = SCNVector3(1, 0.1, 1)
                drip.runAction(.sequence([.wait(duration: 0.3),
                                          .group([.scale(to: 1, duration: 1.4),
                                                  .moveBy(x: 0, y: -0.25, z: 0, duration: 1.4)])]))
                splats.addChildNode(drip)
            }
        }
    }

    func clearCream() {
        splats.childNodes.forEach { $0.removeFromParentNode() }
    }

    var creamLevel: Int { splats.childNodes.count }

    // MARK: - Looks

    /// Soaked: glossy, a little darker, dripping for a few seconds.
    func setWet(_ wet: Bool, in scene: SCNScene? = nil) {
        guard let m = head.geometry?.firstMaterial else { return }
        m.roughness.contents = wet ? 0.18 : 0.55
        m.clearCoat.contents = wet ? 0.9 : 0.05
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
