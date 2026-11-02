import SceneKit
import GLTFKit2
import simd

/// Realistic, skinned bodies generated as glTF models (`Models/body-*.glb`, heads cut off at the
/// neck). They stand in for the toy bodies: same anchor (neck at y = 0, feet ≈ y −2.5) and the
/// same `BodyParts`, so games don't change. Arms are driven through proxy nodes that point down
/// from the shoulder like the toy arms did; a constraint maps each proxy's rotation onto the
/// model's own arm bone.
enum RealBody {
    /// Which body each default character wears; anyone else gets the hoodie.
    static func modelName(for character: GameCharacter) -> String {
        switch character.name {
        case "Grandpa Gus", "Sir Reginald": return "body-gus"
        case "Aunt Linda", "Disco Dolores": return "body-linda"
        case "Coach Brick": return "body-coach"
        case "Baby Benny": return "body-baby"
        default: return "body-hoodie"
        }
    }

    private static var assets: [String: GLTFAsset] = [:]

    private static func asset(_ name: String) -> GLTFAsset? {
        if let a = assets[name] { return a }
        guard let url = Bundle.main.url(forResource: name, withExtension: "glb"),
              let a = try? GLTFAsset(url: url, options: [:]) else { return nil }
        assets[name] = a
        return a
    }

    /// A fresh copy of a model's node tree (skinned meshes can't be shared between instances).
    static func load(_ name: String) -> SCNNode? {
        guard let asset = asset(name), let scene = GLTFSCNSceneSource(asset: asset).defaultScene else { return nil }
        let root = SCNNode()
        for child in scene.rootNode.childNodes { root.addChildNode(child) }
        return root
    }

    private static var props: [String: SCNNode] = [:]

    /// A clone of a static (unskinned) prop model, e.g. "pie" or "mallet".
    static func prop(_ name: String) -> SCNNode? {
        if let p = props[name] { return p.clone() }
        guard let p = load(name) else { return nil }
        props[name] = p
        return p.clone()
    }

    static func build(for character: GameCharacter, legs: LegPose) -> BodyParts? {
        guard let model = load(modelName(for: character)) else { return nil }
        func bone(_ n: String) -> SCNNode? { model.childNode(withName: n, recursively: true) }
        guard let neck = bone("neck"), let armL = bone("LeftArm"), let armR = bone("RightArm"),
              let foreL = bone("LeftForeArm"), let foreR = bone("RightForeArm") else { return nil }
        func pos(_ n: SCNNode) -> simd_float3 { model.simdConvertPosition(.zero, from: n) }

        let g = SCNNode()
        // Scale so neck-to-feet matches the toy body, and sit the neck stump just under the head.
        let neckY = pos(neck).y
        let s = 2.5 / max(neckY, 0.1)
        let holder = SCNNode()
        holder.scale = SCNVector3(s, s, s)
        holder.position = SCNVector3(0, -neckY * s - 0.06, 0)
        holder.addChildNode(model)
        g.addChildNode(holder)

        // Out of the A-pose: let the arms hang at the sides, slightly away from the hips.
        let side: Float = pos(armL).x > 0 ? 1 : -1   // which way the model's left arm points
        lower(armL, toward: simd_normalize(simd_float3(side * 0.16, -1, 0.02)), elbow: foreL, in: model)
        lower(armR, toward: simd_normalize(simd_float3(-side * 0.16, -1, 0.02)), elbow: foreR, in: model)
        // Relaxed elbows: forearms hang down and a touch forward, hands at the thighs.
        if let handL = bone("LeftHand"), let handR = bone("RightHand") {
            lower(foreL, toward: simd_normalize(simd_float3(side * 0.05, -1, 0.18)), elbow: handL, in: model)
            lower(foreR, toward: simd_normalize(simd_float3(-side * 0.05, -1, 0.18)), elbow: handR, in: model)
        }
        // glTF's +X is the model's left; our toy armL sat at −X, so map by side.
        let leftIsNegX = pos(armL).x < 0
        let proxies = [leftIsNegX ? armL : armR, leftIsNegX ? armR : armL].map { proxy(for: $0, in: g) }

        if legs == .sitting {
            for side in ["Left", "Right"] {
                guard let up = bone("\(side)UpLeg"), let low = bone("\(side)Leg"), let foot = bone("\(side)Foot") else { continue }
                lower(up, toward: simd_normalize(simd_float3(0, -0.12, 1)), elbow: low, in: model)
                lower(low, toward: simd_normalize(simd_float3(0, -1, 0.12)), elbow: foot, in: model)
            }
        }

        // The character's own skin at the neck, so a photo head never meets a mismatched neck.
        let neckPost = Accessories.node(SCNCylinder(radius: 0.085, height: 0.26), Fabric.skin(UIColor(rgb: character.meta.skinRGB)),
                                        at: SCNVector3(0, -0.06, 0))
        g.addChildNode(neckPost)
        g.enumerateHierarchy { n, _ in n.castsShadow = true }
        return BodyParts(node: g, armL: proxies[0], armR: proxies[1])
    }

    /// Two-bone arm IK: each frame the shoulder and elbow turn so the hand reaches its target node
    /// (a boxing glove), elbows bending down and out. Replaces the proxy arm constraints.
    static func reach(body: SCNNode, left: SCNNode, right: SCNNode) {
        for sideName in ["Left", "Right"] {
            guard let upper = body.childNode(withName: "\(sideName)Arm", recursively: true),
                  let fore = body.childNode(withName: "\(sideName)ForeArm", recursively: true),
                  let hand = body.childNode(withName: "\(sideName)Hand", recursively: true) else { continue }
            // Rest pose in body space.
            func p(_ n: SCNNode) -> simd_float3 { body.simdConvertPosition(.zero, from: n) }
            let s0 = p(upper), e0 = p(fore), h0 = p(hand)
            let l1 = simd_length(e0 - s0), l2 = simd_length(h0 - e0)
            let bodyQ = body.simdWorldOrientation
            let upperRest = bodyQ.inverse * upper.simdWorldOrientation, foreRest = bodyQ.inverse * fore.simdWorldOrientation
            let upperDir = simd_normalize(e0 - s0), foreDir = simd_normalize(h0 - e0)
            // Which side of the body this arm is on, for the elbow's pole.
            let sideSign: Float = s0.x < 0 ? -1 : 1
            // The glove on the same side (gloves are placed at −x / +x in the fighter's space).
            let target = (left.simdPosition.x < 0) == (sideSign < 0) ? left : right

            func solve() -> (simd_float3, simd_float3) {   // world upper dir, world fore dir
                let b = body.presentation
                let q = b.simdWorldOrientation
                let s = upper.presentation.simdWorldPosition
                let t = target.presentation.simdWorldPosition
                let scale = simd_length(b.simdConvertVector(simd_float3(1, 0, 0), to: nil))
                let L1 = l1 * scale, L2 = l2 * scale
                var toT = t - s
                let d = max(0.05, min(simd_length(toT), (L1 + L2) * 0.999))
                toT = simd_normalize(toT)
                let a = acos(max(-1, min(1, (L1 * L1 + d * d - L2 * L2) / (2 * L1 * d))))
                var pole = q.act(simd_normalize(simd_float3(sideSign * 0.7, -1, -0.2)))
                pole = simd_normalize(pole - simd_dot(pole, toT) * toT)
                let elbow = s + L1 * (cos(a) * toT + sin(a) * pole)
                return (simd_normalize(elbow - s), simd_normalize(s + toT * d - elbow))
            }
            func constraint(rest: simd_quatf, restDir: simd_float3, pick: @escaping ((simd_float3, simd_float3)) -> simd_float3) -> SCNTransformConstraint {
                SCNTransformConstraint.orientationConstraint(inWorldSpace: true) { _, _ in
                    let q = body.presentation.simdWorldOrientation
                    let want = pick(solve())
                    let r = simd_quatf(from: q.act(restDir), to: want) * (q * rest)
                    return SCNQuaternion(r.imag.x, r.imag.y, r.imag.z, r.real)
                }
            }
            upper.constraints = [constraint(rest: upperRest, restDir: upperDir) { $0.0 }]
            fore.constraints = [constraint(rest: foreRest, restDir: foreDir) { $0.1 }]
        }
    }

    /// Rotates `bone` (in model space) so the segment from it to `elbow` points along `dir`.
    private static func lower(_ bone: SCNNode, toward dir: simd_float3, elbow: SCNNode, in model: SCNNode) {
        let a = model.simdConvertPosition(.zero, from: bone), b = model.simdConvertPosition(.zero, from: elbow)
        let current = simd_normalize(b - a)
        let q = simd_quatf(from: current, to: dir)
        let modelQ = model.simdWorldOrientation
        // World-space rotation about the bone's own pivot.
        let worldQ = modelQ * q * modelQ.inverse
        bone.simdWorldOrientation = worldQ * bone.simdWorldOrientation
    }

    /// A node at the shoulder whose rest pose points straight down its −Y (like the toy arms).
    /// Rotating it rotates the real arm bone by the same amount in world space.
    private static func proxy(for bone: SCNNode, in body: SCNNode) -> SCNNode {
        let p = SCNNode()
        p.simdPosition = body.simdConvertPosition(.zero, from: bone)
        body.addChildNode(p)
        let restBone = bone.simdWorldOrientation
        let restProxy = p.simdWorldOrientation
        let offset = restProxy.inverse * restBone
        bone.constraints = [SCNTransformConstraint.orientationConstraint(inWorldSpace: true) { _, _ in
            let q = p.presentation.simdWorldOrientation * offset
            return SCNQuaternion(q.imag.x, q.imag.y, q.imag.z, q.real)
        }]
        return p
    }
}

#if DEBUG
/// `-modelPreview <name>`: shows one bundled model from four sides (simulator checks).
enum ModelPreview {
    static func scene(_ name: String) -> (SCNScene, SCNNode)? {
        guard let model = RealBody.load(name) else { return nil }
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.85, alpha: 1)
        let (minB, maxB) = model.boundingBox
        let size = max(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
        let center = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
        for k in 0..<4 {
            let holder = SCNNode()
            let copy = k == 0 ? model : (RealBody.load(name) ?? model.clone())
            copy.position = SCNVector3(-center.x, -center.y, -center.z)
            holder.addChildNode(copy)
            holder.eulerAngles.y = Float(k) * .pi / 2
            holder.position = SCNVector3(Float(k % 2) * size * 1.2 - size * 0.6, Float(k / 2) * -size * 1.2 + size * 0.6, 0)
            scene.rootNode.addChildNode(holder)
        }
        let camera = Effects.makeCamera(fov: 40)
        camera.position = SCNVector3(0, 0, size * 4.2)
        scene.rootNode.addChildNode(camera)
        CandySet.light(scene, rim: .white, camera: camera)
        return (scene, camera)
    }
}
#endif
