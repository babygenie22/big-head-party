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

/// Cloth and trim for the toy bodies: a fine knit normal map so shirts and pants read as fabric
/// (soft light falloff, tiny ribs) instead of flat plastic.
enum Fabric {
    static let knitNormal: UIImage = {
        let n = 128
        return UIGraphicsImageRenderer(size: CGSize(width: n, height: n)).image { ctx in
            // Vertical ribs: each column's normal tilts left then right, plus a faint row stitch.
            for x in 0..<n {
                let rib = sin(CGFloat(x) / CGFloat(n) * 16 * .pi)
                for y in 0..<n {
                    let stitch = sin(CGFloat(y) / CGFloat(n) * 32 * .pi) * 0.25
                    UIColor(red: 0.5 + rib * 0.35, green: 0.5 + stitch * 0.35, blue: 1, alpha: 1).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()

    static func cloth(_ color: UIColor, roughness: CGFloat = 0.9, repeats: Float = 7) -> SCNMaterial {
        let m = Accessories.material(color, roughness: roughness)
        m.normal.contents = knitNormal
        m.normal.intensity = 0.3
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.contentsTransform = SCNMatrix4MakeScale(repeats, repeats, 1)
        return m
    }

    /// Skin for hands and necks, matching the head's sheen and pores.
    static func skin(_ color: UIColor) -> SCNMaterial {
        let m = Accessories.material(color, roughness: HeadRig.dryRoughness)
        m.normal.contents = Effects.skinNormalMap
        m.normal.intensity = 0.3
        return m
    }

    /// Glossy, clear-coated plastic for shoes and gloves.
    static func glossy(_ color: UIColor, roughness: CGFloat = 0.35) -> SCNMaterial {
        let m = Accessories.material(color, roughness: roughness)
        m.clearCoat.contents = 0.6
        m.clearCoatRoughness.contents = 0.15
        return m
    }

    /// Round chest patch with the character's initial, like a team badge.
    static func badge(_ letter: String, fill: UIColor, ink: UIColor) -> SCNMaterial {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { _ in
            UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 248, height: 248)).fill()
            fill.setFill(); UIBezierPath(ovalIn: CGRect(x: 22, y: 22, width: 212, height: 212)).fill()
            let font = UIFont(name: "BricolageGrotesque-96ptExtraBold", size: 150) ?? .systemFont(ofSize: 150, weight: .black)
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: style]
            let h = (letter as NSString).size(withAttributes: attrs).height
            (letter as NSString).draw(in: CGRect(x: 0, y: (256 - h) / 2 - 6, width: 256, height: h + 12), withAttributes: attrs)
        }
        let m = Accessories.material(.white, roughness: 0.7)
        m.diffuse.contents = image
        m.transparent.contents = image   // round, not square
        return m
    }
}

/// A proportioned body that hangs from the neck at y = 0 (shoulders ≈ 1.4 wide, feet ≈ y −2.5).
enum BodyBuilder {
    static func build(shirt: UIColor, skin: UIColor, legs: LegPose, initial: String? = nil) -> BodyParts {
        let g = SCNNode()
        let shirtM = Fabric.cloth(shirt)
        let skinM = Fabric.skin(skin)
        let pantsColor = UIColor(red: 0.36, green: 0.30, blue: 0.52, alpha: 1)
        let pants = Fabric.cloth(pantsColor, roughness: 0.85, repeats: 9)
        let shoe = Fabric.glossy(.white, roughness: 0.45)   // candy sneakers
        let coral = Fabric.glossy(UIColor(red: 1, green: 0.42, blue: 0.29, alpha: 1), roughness: 0.4)

        g.addChildNode(Accessories.node(SCNCylinder(radius: 0.13, height: 0.32), skinM, at: SCNVector3(0, -0.04, 0)))
        // A soft bean of a torso, like a vinyl toy, with a ribbed collar and a hem band.
        let chest = Accessories.node(SCNSphere(radius: 0.66), shirtM, at: SCNVector3(0, -0.78, 0))
        chest.scale = SCNVector3(0.96, 1.04, 0.74)
        g.addChildNode(chest)
        let shoulders = Accessories.node(SCNCapsule(capRadius: 0.2, height: 1.22), shirtM, at: SCNVector3(0, -0.36, 0))
        shoulders.eulerAngles.z = .pi / 2
        shoulders.scale = SCNVector3(1, 1, 0.8)
        g.addChildNode(shoulders)
        let trim = Fabric.cloth(shirt.darker(0.78), repeats: 8)
        g.addChildNode(Accessories.node(SCNTorus(ringRadius: 0.15, pipeRadius: 0.05), trim, at: SCNVector3(0, -0.17, 0.02)))
        let hem = Accessories.node(SCNTorus(ringRadius: 0.5, pipeRadius: 0.07), trim, at: SCNVector3(0, -1.3, 0))
        hem.scale = SCNVector3(1, 1, 0.78)
        g.addChildNode(hem)
        if let initial, !initial.isEmpty {
            let patch = Accessories.node(SCNPlane(width: 0.34, height: 0.34),
                                         Fabric.badge(initial, fill: shirt.darker(0.78), ink: .white),
                                         at: SCNVector3(0.2, -0.62, 0.468))
            patch.eulerAngles = SCNVector3(-0.22, 0.42, 0)
            g.addChildNode(patch)
        }

        var arms: [SCNNode] = []
        for s: Float in [-1, 1] {
            let arm = SCNNode()
            arm.position = SCNVector3(s * 0.62, -0.36, 0)
            arm.eulerAngles.z = s * 0.14
            arm.addChildNode(Accessories.node(SCNCapsule(capRadius: 0.15, height: 0.66), shirtM, at: SCNVector3(0, -0.28, 0)))
            let cuff = Accessories.node(SCNTorus(ringRadius: 0.135, pipeRadius: 0.04), trim, at: SCNVector3(0, -0.56, 0))
            arm.addChildNode(cuff)
            arm.addChildNode(Accessories.node(SCNCapsule(capRadius: 0.11, height: 0.6), skinM, at: SCNVector3(0, -0.8, 0)))
            // Round mitten hands (with a thumb) read friendlier than fingers at this size.
            let hand = Accessories.node(SCNSphere(radius: 0.17), skinM, at: SCNVector3(0, -1.14, 0.03))
            hand.scale = SCNVector3(0.9, 1, 0.75)
            arm.addChildNode(hand)
            let thumb = Accessories.node(SCNCapsule(capRadius: 0.055, height: 0.2), skinM, at: SCNVector3(-s * 0.1, -1.06, 0.1))
            thumb.eulerAngles = SCNVector3(0.4, 0, -s * 0.7)
            arm.addChildNode(thumb)
            g.addChildNode(arm)
            arms.append(arm)
        }

        if legs != .none {
            for s: Float in [-1, 1] {
                let leg = SCNNode()
                leg.position = SCNVector3(s * 0.23, -1.32, legs == .sitting ? 0.12 : 0)
                if legs == .sitting { leg.eulerAngles.x = -0.35 }
                leg.addChildNode(Accessories.node(SCNCapsule(capRadius: 0.18, height: 1.27), pants, at: SCNVector3(0, -0.62, 0)))
                leg.addChildNode(Accessories.node(SCNTorus(ringRadius: 0.17, pipeRadius: 0.035),
                                                  Fabric.cloth(pantsColor.darker(0.8), repeats: 8), at: SCNVector3(0, -1.02, 0)))
                // Chunky rounded sneakers: rubber toe cap, coral laces and sole.
                let sneaker = Accessories.node(SCNSphere(radius: 0.2), shoe, at: SCNVector3(0, -1.18, 0.1))
                sneaker.scale = SCNVector3(0.95, 0.55, 1.45)
                leg.addChildNode(sneaker)
                let toe = Accessories.node(SCNSphere(radius: 0.13), Fabric.glossy(UIColor(white: 0.94, alpha: 1), roughness: 0.3),
                                           at: SCNVector3(0, -1.2, 0.3))
                toe.scale = SCNVector3(1.3, 0.62, 0.9)
                leg.addChildNode(toe)
                for i in 0..<2 {
                    let lace = Accessories.node(SCNCapsule(capRadius: 0.022, height: 0.2), coral,
                                                at: SCNVector3(0, -1.08 - Float(i) * 0.015, 0.12 + Float(i) * 0.08))
                    lace.eulerAngles = SCNVector3(0.5, 0, .pi / 2)
                    leg.addChildNode(lace)
                }
                let sole = Accessories.node(SCNCylinder(radius: 0.19, height: 0.05), coral, at: SCNVector3(0, -1.26, 0.1))
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
            // Realistic skinned body when its model is bundled; the toy body otherwise.
            let b = RealBody.build(for: character, legs: legs)
                ?? BodyBuilder.build(shirt: UIColor(rgb: character.meta.shirtRGB), skin: UIColor(rgb: character.meta.skinRGB), legs: legs,
                                     initial: character.name.first.map(String.init))
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
