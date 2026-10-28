import SceneKit
import UIKit

/// Hats, 3D hair volume and googly eyes. All coordinates are head-model space
/// (crown at y ≈ 1.28, eyes at y ≈ 0.1, face toward +Z).
enum Accessories {
    static func attach(to rig: HeadRig) {
        let meta = rig.character.meta
        let hairColor = UIColor(rgb: meta.hairRGB)
        if let hair = hairNode(meta.hairVolume, color: hairColor) { rig.head.addChildNode(hair) }
        let lift: Float = meta.hairVolume == .afro ? 0.8 : (meta.hairVolume == .pompadour ? 0.2 : 0)
        if let hat = hatNode(meta.hat) {
            hat.position.y += lift
            rig.head.addChildNode(hat)
        }
        if meta.googlyEyes { addGooglyEyes(to: rig) }
    }

    static func material(_ color: UIColor, roughness: CGFloat = 0.5, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    static func node(_ geometry: SCNGeometry, _ mat: SCNMaterial, at p: SCNVector3) -> SCNNode {
        geometry.materials = [mat]
        let n = SCNNode(geometry: geometry)
        n.position = p
        return n
    }

    static func hatNode(_ style: HatStyle) -> SCNNode? {
        let hat = SCNNode()
        hat.name = "hat"
        switch style {
        case .none:
            return nil
        case .partyHat:
            let stripes = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { ctx in
                UIColor(red: 1, green: 0.25, blue: 0.6, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
                UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1).setFill()
                for i in stride(from: -256, to: 512, by: 64) {
                    let p = UIBezierPath()
                    p.move(to: CGPoint(x: i, y: 0)); p.addLine(to: CGPoint(x: i + 28, y: 0))
                    p.addLine(to: CGPoint(x: i + 28 + 256, y: 256)); p.addLine(to: CGPoint(x: i + 256, y: 256)); p.close(); p.fill()
                }
            }
            let m = material(.white, roughness: 0.6)
            m.diffuse.contents = stripes
            hat.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.42, height: 1.0), m, at: SCNVector3(0, 0.5, 0)))
            hat.addChildNode(node(SCNSphere(radius: 0.13), material(.white, roughness: 0.9), at: SCNVector3(0, 1.02, 0)))
            hat.position = SCNVector3(0.18, 1.05, 0.05)
            hat.eulerAngles.z = -0.28
        case .topHat:
            let black = material(UIColor(white: 0.08, alpha: 1), roughness: 0.35)
            hat.addChildNode(node(SCNCylinder(radius: 0.95, height: 0.05), black, at: SCNVector3(0, 0, 0)))
            hat.addChildNode(node(SCNCylinder(radius: 0.6, height: 0.95), black, at: SCNVector3(0, 0.5, 0)))
            hat.addChildNode(node(SCNCylinder(radius: 0.615, height: 0.16), material(UIColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1)), at: SCNVector3(0, 0.1, 0)))
            hat.position = SCNVector3(0, 1.08, -0.05)
            hat.eulerAngles = SCNVector3(-0.12, 0, 0.12)
        case .crown:
            let gold = material(UIColor(red: 1, green: 0.78, blue: 0.2, alpha: 1), roughness: 0.25, metalness: 1)
            hat.addChildNode(node(SCNTube(innerRadius: 0.55, outerRadius: 0.6, height: 0.3), gold, at: SCNVector3(0, 0, 0)))
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi
                hat.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.11, height: 0.28), gold,
                                      at: SCNVector3(0.575 * sin(a), 0.29, 0.575 * cos(a))))
                hat.addChildNode(node(SCNSphere(radius: 0.06), material(i % 2 == 0 ? .systemRed : .systemBlue, roughness: 0.1),
                                      at: SCNVector3(0.61 * sin(a), 0.02, 0.61 * cos(a))))
            }
            hat.position = SCNVector3(0, 1.18, -0.02)
            hat.eulerAngles.z = 0.1
        case .headband:
            let band = node(SCNTorus(ringRadius: 1.0, pipeRadius: 0.09), material(UIColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1), roughness: 0.9),
                            at: SCNVector3(0, 0.62, -0.06))
            band.scale = SCNVector3(0.96, 1, 1.02)
            hat.addChildNode(band)
        case .cowboy:
            let leather = material(UIColor(red: 0.55, green: 0.35, blue: 0.18, alpha: 1), roughness: 0.8)
            let brim = node(SCNCylinder(radius: 1.35, height: 0.05), leather, at: SCNVector3(0, 0, 0))
            brim.scale = SCNVector3(1, 1, 0.85)
            hat.addChildNode(brim)
            let crown = node(SCNCapsule(capRadius: 0.62, height: 1.25), leather, at: SCNVector3(0, 0.25, 0))
            crown.scale = SCNVector3(1, 0.7, 0.9)
            hat.addChildNode(crown)
            hat.addChildNode(node(SCNCylinder(radius: 0.64, height: 0.12), material(UIColor(white: 0.15, alpha: 1)), at: SCNVector3(0, 0.08, 0)))
            hat.position = SCNVector3(0, 1.0, -0.05)
            hat.eulerAngles.x = -0.15
        }
        return hat
    }

    static func hairNode(_ volume: HairVolume, color: UIColor) -> SCNNode? {
        let m = material(color, roughness: 0.95)
        let hair = SCNNode()
        hair.name = "hair"
        switch volume {
        case .none:
            return nil
        case .afro:
            hair.addChildNode(node(SCNSphere(radius: 1.2), m, at: SCNVector3(0, 0.95, -0.35)))
            // Curly bumps.
            var rng = SeededRandom(seed: 42)
            for _ in 0..<60 {
                let theta = Float(rng.next()) * 2 * .pi
                let phi = Float(rng.next()) * 0.55 * .pi
                let dir = SCNVector3(cos(theta) * sin(phi), cos(phi), sin(theta) * sin(phi))
                if dir.z > 0.55 && dir.y < 0.5 { continue }   // keep the forehead clear
                hair.addChildNode(node(SCNSphere(radius: 0.32), m,
                                       at: SCNVector3(dir.x * 1.12, 0.95 + dir.y * 1.12, -0.35 + dir.z * 1.12)))
            }
        case .bun:
            hair.addChildNode(node(SCNSphere(radius: 0.42), m, at: SCNVector3(0, 1.38, -0.5)))
            hair.addChildNode(node(SCNTorus(ringRadius: 0.3, pipeRadius: 0.08), m, at: SCNVector3(0, 1.1, -0.42)))
        case .pompadour:
            let swoop = node(SCNCapsule(capRadius: 0.42, height: 1.3), m, at: SCNVector3(0, 1.12, 0.3))
            swoop.eulerAngles.z = .pi / 2
            hair.addChildNode(swoop)
            hair.addChildNode(node(SCNSphere(radius: 0.55), m, at: SCNVector3(0, 1.05, -0.2)))
        }
        return hair
    }

    static func addGooglyEyes(to rig: HeadRig) {
        for u in [FaceLayout.leftEye.x, FaceLayout.rightEye.x] {
            let x = HeadMeshBuilder.modelX(u: u), y = rig.anchors.eyeY
            let hits = rig.head.hitTestWithSegment(from: SCNVector3(x, y, 3), to: SCNVector3(x, y, -0.5), options: nil)
            let z = hits.first(where: { $0.node === rig.head })?.localCoordinates.z ?? 0.9
            let eye = node(SCNSphere(radius: 0.17), material(.white, roughness: 0.2), at: SCNVector3(x, y, z + 0.06))
            eye.scale = SCNVector3(1, 1, 0.5)
            let pupil = node(SCNSphere(radius: 0.08), material(.black, roughness: 0.2), at: SCNVector3(0, -0.05, 0.14))
            pupil.runAction(.repeatForever(.sequence([
                .move(to: SCNVector3(0.05, -0.06, 0.14), duration: 0.18),
                .move(to: SCNVector3(-0.06, -0.04, 0.14), duration: 0.22),
                .move(to: SCNVector3(0.0, -0.08, 0.14), duration: 0.15),
            ])))
            eye.addChildNode(pupil)
            rig.head.addChildNode(eye)
        }
    }

    /// Simple torso for games. Bodies are deliberately minimal — the face is the star.
    static func torso(color: UIColor, skin: UIColor) -> SCNNode {
        let body = SCNNode()
        let shirt = material(color, roughness: 0.8)
        let chest = node(SCNCapsule(capRadius: 0.55, height: 1.7), shirt, at: SCNVector3(0, -0.75, 0))
        chest.scale = SCNVector3(1.15, 1, 0.8)
        body.addChildNode(chest)
        body.addChildNode(node(SCNCylinder(radius: 0.22, height: 0.4), material(skin, roughness: 0.7), at: SCNVector3(0, 0.05, 0)))
        return body
    }
}
