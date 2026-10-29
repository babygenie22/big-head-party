import SceneKit
import UIKit

/// Throws a cream pie in an arc at a head and plays the full splat reaction.
enum PieThrower {
    static func throwPie(at rig: HeadRig, in scene: SCNScene, camera: SCNNode?, from start: SCNVector3,
                         scale: Float, flight: TimeInterval = 0.6, completion: (() -> Void)? = nil) {
        let target = rig.faceWorldPosition
        let pie = Effects.makePie()
        pie.scale = SCNVector3(scale, scale, scale)
        pie.position = start
        scene.rootNode.addChildNode(pie)

        rig.hold(.mouthOpen, weight: 0.9, duration: 0.35)   // the "oh no" face
        let up = SCNVector3(0, 1, 0)
        let front = SCNVector3(0, 0, 1)                      // the pie's cream side
        let height = max(0.6, hypotf(target.z - start.z, target.x - start.x) * 0.18)
        pie.runAction(.customAction(duration: flight) { node, t in
            let p = Float(t) / Float(flight)
            node.position = SCNVector3(start.x + (target.x - start.x) * p,
                                       start.y + (target.y - start.y) * p + sin(p * .pi) * height,
                                       start.z + (target.z - start.z) * p)
            node.look(at: target, up: up, localFront: front)
        }) {
            DispatchQueue.main.async {
                impact(pie: pie, on: rig, at: target, in: scene, camera: camera)
                completion?()
            }
        }
    }

    private static func impact(pie: SCNNode, on rig: HeadRig, at point: SCNVector3, in scene: SCNScene, camera: SCNNode?) {
        rig.hold(.mouthOpen, weight: 0, duration: 0.05)
        rig.pulse(.squish, peak: 1.0, attack: 0.04, hold: 0.2, release: 0.8)
        rig.wobbleHit(sideways: Float.random(in: -0.4...0.4), back: 1, strength: 1)
        rig.splatCream()
        Effects.burst(in: scene, at: point, color: UIColor(red: 1, green: 0.98, blue: 0.92, alpha: 1), count: 120,
                      velocity: 5, size: 0.09, direction: SCNVector3(0, 0.4, 1), spread: 85)
        if let camera { Effects.shake(camera, intensity: 0.1) }
        Effects.haptic(.heavy)

        // The tin sticks to the face for a beat, then slides off.
        let world = pie.worldTransform
        rig.head.addChildNode(pie)
        pie.setWorldTransform(world)
        pie.runAction(.sequence([
            .wait(duration: 0.8),
            .group([.moveBy(x: 0, y: -2.2, z: 0.6, duration: 0.6),
                    .rotateBy(x: 1.2, y: 0, z: 0.6, duration: 0.6),
                    .fadeOut(duration: 0.6)]),
            .removeFromParentNode(),
        ]))
    }
}
