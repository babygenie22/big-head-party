import SceneKit
import UIKit

/// The game-show set: two contestants behind podiums, neon sign, pie launcher.
/// Used by the Pie-Q Test game and by the attract-mode demo on the intro screen.
final class PieStage {
    let scene = SCNScene()
    let cameraRig = SCNNode()
    let camera = Effects.makeCamera(fov: 38)
    private(set) var contestants: [Contestant] = []
    var rigs: [HeadRig] { contestants.map(\.rig) }
    let podiumX: [Float] = [-1.7, 1.7]
    let neckY: Float = 2.0

    init(characters: [GameCharacter], showSign: Bool = true) {
        cameraRig.addChildNode(camera)
        scene.rootNode.addChildNode(cameraRig)
        Location.gameShow.apply(to: scene, camera: camera)
        buildSet(showSign: showSign)

        for (i, character) in characters.prefix(2).enumerated() {
            let c = Contestant(character: character)
            c.group.position = SCNVector3(podiumX[i], neckY, 0)
            c.group.eulerAngles.y = i == 0 ? 0.22 : -0.22
            scene.rootNode.addChildNode(c.group)
            c.rig.startIdle(seed: Double(i) * 2.1)
            c.rig.prepareCream()
            contestants.append(c)
        }
        focus(on: nil, animated: false)
    }

    private func buildSet(showSign: Bool) {
        // A glossy black stage riser on the studio floor.
        let riser = Accessories.material(UIColor(white: 0.04, alpha: 1), roughness: 0.12)
        riser.clearCoat.contents = 1
        riser.clearCoatRoughness.contents = 0.05
        scene.rootNode.addChildNode(Accessories.node(SCNCylinder(radius: 5.5, height: 0.18), riser, at: SCNVector3(0, 0.09, -0.5)))
        scene.rootNode.addChildNode(Accessories.node(SCNTorus(ringRadius: 5.5, pipeRadius: 0.03), Surface.chrome, at: SCNVector3(0, 0.18, -0.5)))

        // Marquee bulbs.
        let bulbOn = SCNMaterial()
        bulbOn.lightingModel = .physicallyBased
        bulbOn.diffuse.contents = UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 1)
        bulbOn.emission.contents = UIColor(red: 1, green: 0.8, blue: 0.45, alpha: 1)
        bulbOn.emission.intensity = 2.5
        for i in 0..<28 {
            let a = Float(i) / 27 * .pi
            let bulb = SCNNode(geometry: SCNSphere(radius: 0.08))
            bulb.geometry?.materials = [bulbOn]
            bulb.position = SCNVector3(-cos(a) * 5.2, 2.2 + sin(a) * 3.6, -3.8)
            bulb.runAction(.repeatForever(.sequence([.wait(duration: Double(i % 4) * 0.2),
                                                     .fadeOpacity(to: 0.3, duration: 0.25),
                                                     .fadeOpacity(to: 1, duration: 0.25),
                                                     .wait(duration: 0.4)])))
            scene.rootNode.addChildNode(bulb)
        }

        // Podiums.
        let colors: [UIColor] = [UIColor(red: 0.08, green: 0.2, blue: 0.55, alpha: 1), UIColor(red: 0.6, green: 0.06, blue: 0.1, alpha: 1)]
        for (i, x) in podiumX.enumerated() {
            let podium = SCNNode(geometry: SCNBox(width: 1.9, height: 1.55, length: 1.0, chamferRadius: 0.08))
            podium.geometry?.materials = [Surface.paintedMetal(colors[i])]
            podium.position = SCNVector3(x, 0.775, 0.55)
            let stripe = SCNNode(geometry: SCNBox(width: 1.95, height: 0.12, length: 1.04, chamferRadius: 0.02))
            // LED strip.
            let glow = SCNMaterial()
            glow.lightingModel = .physicallyBased
            glow.diffuse.contents = UIColor.white
            glow.emission.contents = UIColor(white: 1, alpha: 1)
            glow.emission.intensity = 1.6
            stripe.geometry?.materials = [glow]
            stripe.position = SCNVector3(0, 0.55, 0)
            podium.addChildNode(stripe)
            let buzzer = SCNNode(geometry: SCNCylinder(radius: 0.22, height: 0.1))
            buzzer.geometry?.materials = [Surface.plastic(UIColor(red: 0.85, green: 0.05, blue: 0.05, alpha: 1))]
            podium.addChildNode(Accessories.node(SCNCylinder(radius: 0.27, height: 0.06), Surface.chrome, at: SCNVector3(0, 0.79, 0.1)))
            buzzer.position = SCNVector3(0, 0.82, 0.1)
            podium.addChildNode(buzzer)
            scene.rootNode.addChildNode(podium)
        }
    }

    // MARK: - Camera

    func focus(on index: Int?, animated: Bool = true) {
        let position: SCNVector3
        let target: SCNVector3
        if let index, index < contestants.count {
            let shot = contestants[index].closeUp()
            position = shot.position
            target = shot.target
        } else {
            position = SCNVector3(0, 2.9, 8.8)
            target = SCNVector3(0, 2.4, 0)
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.7 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraRig.position = position
        cameraRig.look(at: target)
        SCNTransaction.commit()
    }

    // MARK: - Pies

    /// Launches a pie at contestant `index`. The completion runs on the main thread after impact.
    func throwPie(at index: Int, completion: (() -> Void)? = nil) {
        guard index < contestants.count else { return }
        let c = contestants[index]
        let target = c.rig.faceWorldPosition
        PieThrower.throwPie(at: c.rig, in: scene, camera: camera,
                            from: SCNVector3(target.x * 0.3 + Float.random(in: -0.6...0.6), 0.6, 8),
                            scale: c.headScale * 1.15, completion: completion)
    }

    func cheer(_ index: Int) {
        guard index < rigs.count else { return }
        let rig = rigs[index]
        Effects.confetti(in: scene, at: SCNVector3(contestants[index].group.position.x, 4.2, 0.5))
        rig.root.runAction(.sequence([.moveBy(x: 0, y: 0.4, z: 0, duration: 0.15), .moveBy(x: 0, y: -0.4, z: 0, duration: 0.25)]))
        rig.pulse(.puff, peak: 0.8)
    }

    func cleanUp() {
        rigs.forEach { $0.clearCream() }
    }
}
