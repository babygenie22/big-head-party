import SceneKit
import UIKit

/// A single head on a spotlight turntable. Used by the home screen, Face Studio and Cast previews.
final class ShowcaseStage {
    let scene = SCNScene()
    let cameraRig = SCNNode()
    let camera = Effects.makeCamera(fov: 34)
    private(set) var rig: HeadRig?
    private let turntable = SCNNode()

    init(character: GameCharacter?, sway: Bool = true) {
        scene.background.contents = UIColor.clear
        Effects.addStudioLights(to: scene)
        cameraRig.addChildNode(camera)
        cameraRig.position = SCNVector3(0, 0.15, 5.6)
        cameraRig.look(at: SCNVector3(0, -0.05, 0))
        scene.rootNode.addChildNode(cameraRig)
        scene.rootNode.addChildNode(turntable)
        if sway {
            turntable.runAction(.repeatForever(.customAction(duration: 12.566) { node, t in
                node.eulerAngles.y = Float(sin(Double(t) * 0.5)) * 0.55
            }))
        }
        if let character { show(character, animated: false) }
    }

    func show(_ character: GameCharacter, animated: Bool = true) {
        rig?.root.removeFromParentNode()
        let newRig = HeadRig(character: character)
        newRig.root.position = SCNVector3(0, -HeadRig.neckOffset, 0)
        turntable.addChildNode(newRig.root)
        newRig.startIdle()
        frame(newRig)
        if animated {
            newRig.root.scale = SCNVector3(0.01, 0.01, 0.01)
            newRig.root.runAction(.sequence([.scale(to: 1.12, duration: 0.25), .scale(to: 0.96, duration: 0.12), .scale(to: 1, duration: 0.1)]))
        }
        rig = newRig
    }

    /// Bottom share of every showcase card covered by overlays (reaction buttons, name labels).
    static let bottomOverlay: Float = 0.22
    static let topMargin: Float = 0.05
    static let designFOV: Float = 34

    /// Frames this head (hat and hair included) from crown to chin above the card's overlays.
    /// A fixed camera suited an average face; longer faces lost their chin behind the buttons.
    private func frame(_ rig: HeadRig) {
        let (lo, hi) = rig.root.boundingBox
        let top = hi.y - HeadRig.neckOffset, bottom = lo.y - HeadRig.neckOffset
        let tanHalf = tan(Self.designFOV * .pi / 360)
        let usable = 1 - Self.bottomOverlay - Self.topMargin
        let span = max((top - bottom) / usable, 2 * 5.6 * tanHalf)   // never closer than the original shot
        let center = top + Self.topMargin * span - span / 2
        cameraRig.position = SCNVector3(0, center + 0.2, span / 2 / tanHalf)
        cameraRig.look(at: SCNVector3(0, center, 0))
    }

    func react(_ morph: Morph) {
        guard let rig else { return }
        switch morph {
        case .skewLeft, .skewRight:
            rig.wobbleHit(sideways: morph == .skewLeft ? -1 : 1, back: 0.2)
        case .squish:
            rig.wobbleHit(sideways: 0, back: 1)
        default:
            break
        }
        rig.pulse(morph, peak: 1, hold: 0.35, release: 0.9)
    }

    func throwPie() {
        guard let rig else { return }
        PieThrower.throwPie(at: rig, in: scene, camera: camera, from: SCNVector3(0.8, -1.5, 7.5), scale: 1.0, flight: 0.5)
    }

    func clean() { rig?.clearCream() }
}
