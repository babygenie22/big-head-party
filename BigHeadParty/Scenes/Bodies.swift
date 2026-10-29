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
        let pants = Accessories.material(UIColor(red: 0.17, green: 0.18, blue: 0.27, alpha: 1), roughness: 0.8)
        let shoe = Accessories.material(UIColor(white: 0.1, alpha: 1), roughness: 0.5)

        g.addChildNode(Accessories.node(SCNCylinder(radius: 0.13, height: 0.32), skinM, at: SCNVector3(0, -0.04, 0)))
        let chest = Accessories.node(SCNCapsule(capRadius: 0.4, height: 1.35), shirtM, at: SCNVector3(0, -0.74, 0))
        chest.scale = SCNVector3(1.3, 1, 0.72)
        g.addChildNode(chest)
        let shoulders = Accessories.node(SCNCapsule(capRadius: 0.17, height: 1.19), shirtM, at: SCNVector3(0, -0.32, 0))
        shoulders.eulerAngles.z = .pi / 2
        shoulders.scale = SCNVector3(1, 1, 0.85)
        g.addChildNode(shoulders)
        g.addChildNode(Accessories.node(SCNTorus(ringRadius: 0.15, pipeRadius: 0.045),
                                        Accessories.material(shirt.darker(0.72), roughness: 0.8), at: SCNVector3(0, -0.17, 0.02)))

        var arms: [SCNNode] = []
        for s: Float in [-1, 1] {
            let arm = SCNNode()
            arm.position = SCNVector3(s * 0.6, -0.32, 0)
            arm.eulerAngles.z = s * 0.1
            arm.addChildNode(Accessories.node(SCNCapsule(capRadius: 0.12, height: 0.74), shirtM, at: SCNVector3(0, -0.32, 0)))
            arm.addChildNode(Accessories.node(SCNCapsule(capRadius: 0.1, height: 0.62), skinM, at: SCNVector3(0, -0.85, 0)))
            let hand = Accessories.node(SCNSphere(radius: 0.13), skinM, at: SCNVector3(0, -1.15, 0.02))
            hand.scale = SCNVector3(0.8, 1.1, 0.55)
            arm.addChildNode(hand)
            g.addChildNode(arm)
            arms.append(arm)
        }

        if legs != .none {
            for s: Float in [-1, 1] {
                let leg = SCNNode()
                leg.position = SCNVector3(s * 0.21, -1.32, legs == .sitting ? 0.12 : 0)
                if legs == .sitting { leg.eulerAngles.x = -0.35 }
                leg.addChildNode(Accessories.node(SCNCapsule(capRadius: 0.16, height: 1.27), pants, at: SCNVector3(0, -0.62, 0)))
                leg.addChildNode(Accessories.node(SCNBox(width: 0.24, height: 0.14, length: 0.42, chamferRadius: 0.04), shoe, at: SCNVector3(0, -1.2, 0.1)))
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
