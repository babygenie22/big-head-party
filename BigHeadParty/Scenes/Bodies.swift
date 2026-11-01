import SceneKit
import UIKit

/// Player setting: cartoon bobbleheads or realistically proportioned heads.
enum HeadSize: String, CaseIterable, Identifiable {
    case big, real
    static let storageKey = "headSize"
    static var current: HeadSize { HeadSize(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .big }
    var id: String { rawValue }
    var label: String { self == .big ? "Big heads" : "Real heads" }
    /// Head-model scale when standing on a body (the head model is ~2.1 units wide).
    var scale: Float { self == .big ? 0.55 : 0.26 }
}

enum LegPose { case none, standing, sitting }

struct BodyParts {
    let node: SCNNode
    let armL: SCNNode
    let armR: SCNNode
}

/// A proportioned body that hangs from the neck at y = 0 (shoulders ≈ 1.4 wide, feet ≈ y −2.5).
enum BodyBuilder {
    static func build(shirt: UIColor, skin: UIColor, legs: LegPose) -> BodyParts {
        let g = SCNNode()
        let shirtM = Accessories.material(shirt, roughness: 0.85)
        let skinM = Accessories.material(skin, roughness: 0.6)
        let pants = Accessories.material(UIColor(red: 0.36, green: 0.30, blue: 0.52, alpha: 1), roughness: 0.8)
        let shoe = Accessories.material(.white, roughness: 0.5)   // candy sneakers

        g.addChildNode(Accessories.node(SCNCylinder(radius: 0.13, height: 0.32), skinM, at: SCNVector3(0, -0.04, 0)))
        // A soft bean of a torso, like a vinyl toy, with a collar and a hem band.
        let chest = Accessories.node(SCNSphere(radius: 0.66), shirtM, at: SCNVector3(0, -0.78, 0))
        chest.scale = SCNVector3(0.96, 1.04, 0.74)
        g.addChildNode(chest)
        let shoulders = Accessories.node(SCNCapsule(capRadius: 0.2, height: 1.22), shirtM, at: SCNVector3(0, -0.36, 0))
        shoulders.eulerAngles.z = .pi / 2
        shoulders.scale = SCNVector3(1, 1, 0.8)
        g.addChildNode(shoulders)
        let trim = Accessories.material(shirt.darker(0.78), roughness: 0.85)
        g.addChildNode(Accessories.node(SCNTorus(ringRadius: 0.15, pipeRadius: 0.05), trim, at: SCNVector3(0, -0.17, 0.02)))
        let hem = Accessories.node(SCNTorus(ringRadius: 0.5, pipeRadius: 0.07), trim, at: SCNVector3(0, -1.3, 0))
        hem.scale = SCNVector3(1, 1, 0.78)
        g.addChildNode(hem)

        var arms: [SCNNode] = []
        for s: Float in [-1, 1] {
            let arm = SCNNode()
            arm.position = SCNVector3(s * 0.62, -0.36, 0)
            arm.eulerAngles.z = s * 0.14
            arm.addChildNode(Accessories.node(SCNCapsule(capRadius: 0.15, height: 0.66), shirtM, at: SCNVector3(0, -0.28, 0)))
            arm.addChildNode(Accessories.node(SCNCapsule(capRadius: 0.11, height: 0.6), skinM, at: SCNVector3(0, -0.8, 0)))
            // Round mitten hands read friendlier than fingers at this size.
            let hand = Accessories.node(SCNSphere(radius: 0.17), skinM, at: SCNVector3(0, -1.14, 0.03))
            hand.scale = SCNVector3(0.9, 1, 0.75)
            arm.addChildNode(hand)
            g.addChildNode(arm)
            arms.append(arm)
        }

        if legs != .none {
            for s: Float in [-1, 1] {
                let leg = SCNNode()
                leg.position = SCNVector3(s * 0.23, -1.32, legs == .sitting ? 0.12 : 0)
                if legs == .sitting { leg.eulerAngles.x = -0.35 }
                leg.addChildNode(Accessories.node(SCNCapsule(capRadius: 0.18, height: 1.27), pants, at: SCNVector3(0, -0.62, 0)))
                // Chunky rounded sneakers with a candy sole.
                let sneaker = Accessories.node(SCNSphere(radius: 0.2), shoe, at: SCNVector3(0, -1.18, 0.1))
                sneaker.scale = SCNVector3(0.95, 0.55, 1.45)
                leg.addChildNode(sneaker)
                let sole = Accessories.node(SCNCylinder(radius: 0.19, height: 0.05), Accessories.material(UIColor(red: 1, green: 0.42, blue: 0.29, alpha: 1), roughness: 0.6),
                                            at: SCNVector3(0, -1.26, 0.1))
                sole.scale = SCNVector3(1, 1, 1.5)
                leg.addChildNode(sole)
                g.addChildNode(leg)
            }
        }
        return BodyParts(node: g, armL: arms[0], armR: arms[1])
    }
}

/// A character in a game: head rig + optional body, grouped under one node placed at the neck.
final class Contestant {
    let character: GameCharacter
    let rig: HeadRig
    let group: SCNNode
    let body: BodyParts?
    let headScale: Float

    init(character: GameCharacter, legs: LegPose = .none, headScale: Float = HeadSize.current.scale,
         withBody: Bool = true, headTurn: Float = 0) {
        let rig = HeadRig(character: character)
        let group = SCNNode()
        var parts: BodyParts?
        if withBody {
            let b = BodyBuilder.build(shirt: UIColor(rgb: character.meta.shirtRGB), skin: UIColor(rgb: character.meta.skinRGB), legs: legs)
            group.addChildNode(b.node)
            parts = b
        }
        rig.root.position = SCNVector3(0, withBody ? 0.08 : 0, 0)
        rig.root.scale = SCNVector3(headScale, headScale, headScale)
        rig.root.eulerAngles.y = headTurn
        group.addChildNode(rig.root)
        group.enumerateHierarchy { node, _ in node.castsShadow = true }
        self.character = character
        self.rig = rig
        self.group = group
        self.body = parts
        self.headScale = headScale
    }

    /// Camera position/target for a close-up on this face, scaled to the head size.
    func closeUp(side: Float = 0.75) -> (position: SCNVector3, target: SCNVector3) {
        let f = rig.faceWorldPosition
        let k = headScale / 0.62
        return (SCNVector3(f.x * side, f.y + 0.25 * k, f.z + 4.0 * k + 0.3), SCNVector3(f.x, f.y - 0.05 * k, f.z))
    }
}

extension SCNNode {
    /// Smoothly moves a camera rig to a new position and target.
    func fly(to position: SCNVector3, lookAt target: SCNVector3, duration: TimeInterval = 0.7) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.position = position
        self.look(at: target)
        SCNTransaction.commit()
    }
}
