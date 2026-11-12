import SceneKit
import UIKit

/// The carnival booth around the dunk tank: a wooden stage with a splash mat, a striped canvas
/// backdrop between barber poles, a "DUNK TANK" marquee, bunting, balloons, a ladder up to the
/// seat, a bucket of balls and a ring of chasing bulbs round the target. Dressing only: the tank,
/// seat and target themselves belong to `DunkGame`.
enum DunkBooth {
    static let blue = UIColor(red: 0.1, green: 0.38, blue: 0.72, alpha: 1)

    /// `tankX` is the tank's center; `target` the middle of the bullseye.
    static func build(in scene: SCNScene, tankX: Float, seat: Float, target: SCNVector3) {
        let root = SCNNode()
        root.name = "dunkBooth"
        scene.rootNode.addChildNode(root)
        let midX = (tankX + target.x) / 2

        // Stage, with a wet-look mat under the tank where the splashes land.
        let wood = Surface.wood(UIColor(red: 0.6, green: 0.42, blue: 0.26, alpha: 1), planks: 8)
        wood.diffuse.contentsTransform = SCNMatrix4MakeScale(1.5, 1, 1)
        wood.roughness.contents = 0.7
        wood.clearCoat.contents = 0.1
        root.addChildNode(Accessories.node(SCNBox(width: 8.6, height: 0.05, length: 5.2, chamferRadius: 0.01), wood, at: SCNVector3(midX, 0.025, 0.4)))
        root.addChildNode(Accessories.node(SCNBox(width: 3.1, height: 0.02, length: 2.5, chamferRadius: 0.01), Surface.plastic(blue),
                                           at: SCNVector3(tankX, 0.06, 0.1)))

        // Striped canvas backdrop between barber poles.
        let canvas = Surface.canvas(.white)
        canvas.diffuse.contents = Fairground.stripes(Fairground.cream, blue, count: 12)
        canvas.diffuse.wrapS = .repeat
        canvas.normal.intensity = 0.3
        canvas.isDoubleSided = true
        let wallZ: Float = -1.75, wallH: Float = 5.4, half: Float = 4.1
        root.addChildNode(Accessories.node(SCNPlane(width: CGFloat(half * 2), height: CGFloat(wallH)), canvas, at: SCNVector3(midX, wallH / 2, wallZ)))
        let pole = Accessories.material(.white, roughness: 0.3)
        pole.diffuse.contents = Fairground.stripes(.white, Fairground.red, count: 2, diagonal: true)
        pole.diffuse.wrapS = .repeat; pole.diffuse.wrapT = .repeat
        pole.diffuse.contentsTransform = SCNMatrix4MakeScale(1, 6, 1)
        pole.clearCoat.contents = 0.6
        for side: Float in [-1, 1] {
            let x = midX + side * half
            root.addChildNode(Accessories.node(SCNCylinder(radius: 0.09, height: CGFloat(wallH + 0.4)), pole, at: SCNVector3(x, (wallH + 0.4) / 2, wallZ + 0.05)))
            root.addChildNode(Accessories.node(SCNSphere(radius: 0.16), Surface.paintedMetal(Fairground.gold), at: SCNVector3(x, wallH + 0.5, wallZ + 0.05)))
        }
        root.addChildNode(Fairground.marquee("DUNK TANK", width: 3.6, height: 0.74, at: SCNVector3(midX, wallH + 0.55, wallZ + 0.1)))
        root.addChildNode(Fairground.bunting(from: SCNVector3(midX - half, wallH + 0.2, wallZ + 0.2), to: SCNVector3(midX + half, wallH + 0.2, wallZ + 0.2),
                                             sag: 0.45, flags: 21))
        Fairground.balloons(root, at: SCNVector3(midX - half + 0.3, 0.1, wallZ + 0.5))

        // Painted rails round the top and bottom of the tank.
        let rail = Surface.paintedMetal(Fairground.red)
        for y: Float in [0.1, 1.9] {
            for z: Float in [-0.8, 0.8] {
                root.addChildNode(Accessories.node(SCNBox(width: 2.3, height: 0.1, length: 0.1, chamferRadius: 0.02), rail, at: SCNVector3(tankX, y, z)))
            }
            for dx: Float in [-1.1, 1.1] {
                root.addChildNode(Accessories.node(SCNBox(width: 0.1, height: 0.1, length: 1.7, chamferRadius: 0.02), rail, at: SCNVector3(tankX + dx, y, 0)))
            }
        }

        // Ladder up the far side to the seat.
        let steel = Surface.steel
        let ladderX = tankX + 1.45
        for z: Float in [-0.62, -0.18] {
            root.addChildNode(Accessories.node(SCNCylinder(radius: 0.035, height: CGFloat(seat + 0.5)), steel, at: SCNVector3(ladderX, (seat + 0.5) / 2, z)))
        }
        for k in 1...6 {
            let rung = Accessories.node(SCNCylinder(radius: 0.025, height: 0.44), steel, at: SCNVector3(ladderX, Float(k) * seat / 6.2, -0.4))
            rung.eulerAngles.x = .pi / 2
            root.addChildNode(rung)
        }

        // Chasing bulbs round the target.
        for k in 0..<14 {
            let a = Float(k) / 14 * 2 * .pi
            root.addChildNode(Fairground.bulb(color: Fairground.bulbColors[0], radius: 0.045,
                                              at: SCNVector3(target.x + cos(a) * 0.66, target.y + sin(a) * 0.66, target.z - 0.02), phase: k % 3))
        }

        // A bucket of balls by the throwing line.
        let bucket = SCNNode()
        bucket.position = SCNVector3(target.x - 0.9, 0.05, 2.2)
        let tin = SCNTube(innerRadius: 0.3, outerRadius: 0.32, height: 0.5)
        bucket.addChildNode(Accessories.node(tin, Surface.paintedMetal(Fairground.gold), at: SCNVector3(0, 0.25, 0)))
        let ball = Accessories.material(UIColor(white: 0.95, alpha: 1), roughness: 0.45)
        var rng = SeededRandom(seed: 8)
        for k in 0..<9 {
            let a = Float(k) / 9 * 2 * .pi, r: Float = k < 6 ? 0.17 : 0.06
            bucket.addChildNode(Accessories.node(SCNSphere(radius: 0.11), ball,
                                                 at: SCNVector3(cos(a) * r, (k < 6 ? 0.42 : 0.56) + Float(rng.next()) * 0.03, sin(a) * r)))
        }
        root.addChildNode(bucket)
    }
}
