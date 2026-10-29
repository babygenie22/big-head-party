import SceneKit
import SwiftUI

/// "Dunk Tank": a crosshair drifts over the target. Hit the bullseye and the person on the plank
/// drops into the water and comes up soaked. Then the roles swap.
final class DunkGame: ObservableObject {
    enum Phase: Equatable { case intro, aiming, flying, finished }

    @Published var phase: Phase = .intro
    @Published var score = [0, 0]
    @Published var half = 0               // 0: player 1 throws at player 2; 1: the reverse
    @Published var ball = 0
    @Published var callout: String?
    @Published var hostLine = ""
    @Published var resultLine = ""

    let ballsPerHalf = 5
    let players: [GameCharacter]
    let vsCPU: Bool
    let scene = SCNScene()
    let cameraRig = SCNNode()
    let camera = Effects.makeCamera(fov: 36)
    weak var view: SCNView?

    private let tankX: Float = 0.9, water: Float = 1.3, seat: Float = 2.32
    private let target = SCNVector3(-1.95, 2.35, 0.25)
    private var seatY: Float { seat + 1.36 }
    private let hinge = SCNNode()
    private let crosshair = SCNNode()
    private var victim: Contestant?
    private let clock = GameClock()
    private var aimTimer: Timer?

    init(players: [GameCharacter], vsCPU: Bool) {
        self.players = players
        self.vsCPU = vsCPU
        buildSet()
        cameraRig.addChildNode(camera)
        scene.rootNode.addChildNode(cameraRig)
    }

    /// The thrower this half: player 1 in the first half, player 2 in the second.
    var thrower: Int { half }
    var isHumanTurn: Bool { !(vsCPU && half == 1) }

    func start() { setupHalf() }

    func stop() {
        clock.cancelAll()
        aimTimer?.invalidate()
    }

    func snapshot() -> UIImage? { view?.snapshot() }

    // MARK: - Flow

    private func setupHalf() {
        victim?.group.removeFromParentNode()
        let v = Contestant(character: players[1 - half], legs: .sitting)
        v.group.position = SCNVector3(tankX, seatY, 0.05)
        v.group.eulerAngles.y = -0.3
        scene.rootNode.addChildNode(v.group)
        v.rig.startIdle()
        victim = v
        hinge.eulerAngles.x = 0
        ball = 0
        let k = v.headScale / 0.55
        cameraRig.fly(to: SCNVector3(-0.45, 2.6 + 0.9 * k, 7.2 + 1.6 * k), lookAt: SCNVector3(-0.45, 2.2 + 0.7 * k, 0),
                      duration: half == 0 ? 0 : 0.7)
        hostLine = half == 0
            ? "\(players[0].name) throws at \(players[1].name). Five balls."
            : "Switch! \(players[1].name) is aiming at \(players[0].name) now."
        clock.after(1.2) { [weak self] in self?.nextBall() }
    }

    private func nextBall() {
        if ball >= ballsPerHalf {
            if half == 0 {
                half = 1
                callout = "Switch!"
                clock.after(1.3) { [weak self] in
                    self?.callout = nil
                    self?.setupHalf()
                }
                return
            }
            return finish()
        }
        phase = .aiming
        var t = Double.random(in: 0...5)
        let speed = 0.9 + Double(ball) * 0.18
        let target = self.target
        aimTimer?.invalidate()
        aimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            t += speed / 60
            self?.crosshair.position = SCNVector3(target.x + 0.48 * Float(sin(t * 2.1)), target.y + 0.44 * Float(sin(t * 3.3 + 1)), target.z + 0.05)
        }
        if !isHumanTurn {
            clock.after(Double.random(in: 0.9...2.5)) { [weak self] in self?.throwBall() }
        }
    }

    func throwBall() {
        guard phase == .aiming else { return }
        aimTimer?.invalidate()
        phase = .flying
        let at = crosshair.position
        let d = hypotf(at.x - target.x, at.y - target.y)
        let bull = d < 0.17, onBoard = d < 0.55
        let from = SCNVector3(-0.6, 1.2, 7.5)
        let ballNode = Accessories.node(SCNSphere(radius: 0.11), Accessories.material(UIColor(white: 0.95, alpha: 1), roughness: 0.45), at: from)
        scene.rootNode.addChildNode(ballNode)
        ballNode.runAction(.customAction(duration: 0.42) { node, elapsed in
            let k = Float(elapsed / 0.42)
            node.position = SCNVector3(from.x + (at.x - from.x) * k, from.y + (at.y - from.y) * k + sin(k * .pi) * 0.7, from.z + (at.z - from.z) * k)
        }) { [weak self] in
            DispatchQueue.main.async { self?.ballLanded(ballNode, bull: bull, onBoard: onBoard) }
        }
    }

    private func ballLanded(_ b: SCNNode, bull: Bool, onBoard: Bool) {
        b.runAction(.sequence([.group([.moveBy(x: CGFloat.random(in: -1...1), y: -2.5, z: 2.5, duration: 0.8), .fadeOut(duration: 0.8)]),
                               .removeFromParentNode()]))
        guard let v = victim else { return }
        if bull {
            callout = "BULLSEYE!"
            dunk(v)
            clock.after(3.6) { [weak self] in self?.advance() }
        } else {
            callout = onBoard ? "Clang! Just off the bullseye." : "Missed the whole target!"
            v.rig.pulse(.puff, peak: 0.9, attack: 0.08, hold: 0.35, release: 0.5)   // smug cheeks
            v.rig.wobbleHit(sideways: Float.random(in: -0.5...0.5), back: -0.5, strength: 0.6)
            clock.after(1.4) { [weak self] in self?.advance() }
        }
    }

    private func advance() {
        callout = nil
        ball += 1
        nextBall()
    }

    private func dunk(_ v: Contestant) {
        score[thrower] += 1
        let G = v.group, top = seatY, under = water - 0.55 - v.headScale * 0.9, bob = water - 0.05
        let splashAt = SCNVector3(tankX, water + 0.1, 0.2)
        v.rig.hold(.mouthOpen, weight: 1, duration: 0.12)
        hinge.runAction(.rotateTo(x: 1.5, y: 0, z: 0, duration: 0.18))
        G.runAction(.customAction(duration: 0.42) { node, elapsed in
            let k = Float(elapsed / 0.42)
            node.position.y = top + (under - top) * k * k
        }) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                Effects.burst(in: self.scene, at: splashAt, color: UIColor(red: 0.49, green: 0.78, blue: 1, alpha: 1), count: 220, velocity: 6,
                              size: 0.12, direction: SCNVector3(0, 1.6, 0.4), spread: 50, lifespan: 1.1)
                Effects.burst(in: self.scene, at: splashAt, color: .white, count: 90, velocity: 4, size: 0.07,
                              direction: SCNVector3(0, 1.4, 0.6), spread: 60, lifespan: 1.0)
                Effects.shake(self.camera, intensity: 0.12)
                Effects.haptic(.heavy)
                v.rig.setWet(true, in: self.scene)
                v.rig.hold(.mouthOpen, weight: 0, duration: 0.2)
                self.clock.after(0.5) {
                    G.runAction(.customAction(duration: 0.7) { node, elapsed in
                        node.position.y = under + (bob - under) * sin(Float(elapsed / 0.7) * .pi / 2)
                    }) {
                        DispatchQueue.main.async { v.rig.pulse(.puff, peak: 1, attack: 0.05, hold: 0.25, release: 0.5) }   // spits water
                    }
                }
                self.clock.after(2.7) {
                    G.runAction(.move(to: SCNVector3(G.position.x, top, G.position.z), duration: 0.6))
                    self.hinge.runAction(.rotateTo(x: 0, y: 0, z: 0, duration: 0.6))
                }
            }
        }
    }

    private func finish() {
        phase = .finished
        aimTimer?.invalidate()
        let a = score[0], b = score[1]
        if a == b {
            resultLine = a == 1 ? "One dunk each. Everybody's wet." : "\(a) dunks each. Everybody's wet."
        } else {
            resultLine = "\(players[a > b ? 0 : 1].name) wins, \(max(a, b)) to \(min(a, b))!"
        }
    }

    // MARK: - Set

    private func buildSet() {
        scene.background.contents = UIColor(red: 0.16, green: 0.1, blue: 0.08, alpha: 1)
        Effects.addStudioLights(to: scene, rim: UIColor(red: 1, green: 0.8, blue: 0.5, alpha: 1))
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.29, green: 0.23, blue: 0.17, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        let back = SCNMaterial()
        back.diffuse.contents = Effects.stripes(UIColor(red: 0.85, green: 0.16, blue: 0.25, alpha: 1), UIColor(red: 0.96, green: 0.94, blue: 0.9, alpha: 1))
        back.roughness.contents = 0.9
        let backNode = SCNNode(geometry: SCNPlane(width: 18, height: 7))
        backNode.geometry?.materials = [back]
        backNode.position = SCNVector3(0, 3.5, -3.6)
        scene.rootNode.addChildNode(backNode)
        let bannerM = SCNMaterial()
        bannerM.lightingModel = .constant
        bannerM.diffuse.contents = Effects.banner("DUNK TANK", background: UIColor(red: 0.17, green: 0.1, blue: 0.07, alpha: 1))
        let banner = SCNNode(geometry: SCNPlane(width: 7, height: 1.75))
        banner.geometry?.materials = [bannerM]
        banner.position = SCNVector3(0, 6.1, -3.5)
        scene.rootNode.addChildNode(banner)

        // Glass tank, steel frame, water with a gently moving surface.
        let glass = SCNMaterial()
        glass.diffuse.contents = UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 1)
        glass.transparency = 0.18
        glass.writesToDepthBuffer = false
        glass.isDoubleSided = true
        let glassNode = SCNNode(geometry: SCNBox(width: 2.2, height: 1.9, length: 1.6, chamferRadius: 0))
        glassNode.geometry?.materials = [glass]
        glassNode.position = SCNVector3(tankX, 0.95, 0)
        glassNode.renderingOrder = 10
        scene.rootNode.addChildNode(glassNode)
        let steel = Accessories.material(UIColor(red: 0.6, green: 0.64, blue: 0.68, alpha: 1), roughness: 0.3, metalness: 0.9)
        for (dx, dz) in [(-1.1, -0.8), (1.1, -0.8), (-1.1, 0.8), (1.1, 0.8)] as [(Float, Float)] {
            scene.rootNode.addChildNode(Accessories.node(SCNBox(width: 0.08, height: 1.95, length: 0.08, chamferRadius: 0), steel,
                                                         at: SCNVector3(tankX + dx, 0.97, dz)))
        }
        let waterM = SCNMaterial()
        waterM.lightingModel = .physicallyBased
        waterM.diffuse.contents = UIColor(red: 0.18, green: 0.56, blue: 0.84, alpha: 1)
        waterM.roughness.contents = 0.08
        waterM.transparency = 0.55
        waterM.writesToDepthBuffer = false
        let body = SCNNode(geometry: SCNBox(width: 2.12, height: CGFloat(water - 0.06), length: 1.52, chamferRadius: 0))
        body.geometry?.materials = [waterM]
        body.position = SCNVector3(tankX, (water - 0.06) / 2 + 0.03, 0)
        body.renderingOrder = 5
        scene.rootNode.addChildNode(body)
        let surfaceGeo = SCNPlane(width: 2.12, height: 1.52)
        surfaceGeo.widthSegmentCount = 24
        surfaceGeo.heightSegmentCount = 18
        let surfaceM = waterM.copy() as! SCNMaterial
        surfaceM.shaderModifiers = [.geometry: "_geometry.position.z += 0.025 * sin(u_time * 2.0 + _geometry.position.x * 3.0);"]
        surfaceGeo.materials = [surfaceM]
        let surface = SCNNode(geometry: surfaceGeo)
        surface.eulerAngles.x = -.pi / 2
        surface.position = SCNVector3(tankX, water, 0)
        surface.renderingOrder = 6
        scene.rootNode.addChildNode(surface)

        // Seat plank on a hinge at its back edge, plus its post.
        hinge.position = SCNVector3(tankX, seat, -0.55)
        hinge.addChildNode(Accessories.node(SCNBox(width: 1.2, height: 0.08, length: 0.75, chamferRadius: 0.01),
                                            Accessories.material(UIColor(red: 0.54, green: 0.38, blue: 0.22, alpha: 1), roughness: 0.8),
                                            at: SCNVector3(0, -0.04, 0.37)))
        scene.rootNode.addChildNode(hinge)
        scene.rootNode.addChildNode(Accessories.node(SCNBox(width: 0.08, height: CGFloat(seat + 0.6), length: 0.08, chamferRadius: 0), steel,
                                                     at: SCNVector3(tankX, (seat + 0.6) / 2, -0.85)))

        // Target with rings, on a post linked to the plank.
        let rings = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512)).image { _ in
            let red = UIColor(red: 0.85, green: 0.16, blue: 0.25, alpha: 1)
            for (r, c) in [(256.0, red), (196.0, UIColor.white), (140.0, red), (80.0, UIColor.white), (45.0, red)] as [(CGFloat, UIColor)] {
                c.setFill()
                UIBezierPath(ovalIn: CGRect(x: 256 - r, y: 256 - r, width: 2 * r, height: 2 * r)).fill()
            }
        }
        let face = SCNMaterial()
        face.diffuse.contents = rings
        face.roughness.contents = 0.6
        let disc = SCNCylinder(radius: 0.55, height: 0.08)
        disc.materials = [Accessories.material(UIColor(white: 0.93, alpha: 1), roughness: 0.5), face, face]
        let targetNode = SCNNode(geometry: disc)
        targetNode.eulerAngles.x = .pi / 2
        targetNode.position = SCNVector3(target.x, target.y, target.z - 0.04)
        scene.rootNode.addChildNode(targetNode)
        scene.rootNode.addChildNode(Accessories.node(SCNCylinder(radius: 0.05, height: CGFloat(target.y)), steel,
                                                     at: SCNVector3(target.x, target.y / 2, target.z - 0.1)))
        scene.rootNode.addChildNode(Accessories.node(SCNBox(width: CGFloat(abs(tankX - target.x)), height: 0.05, length: 0.05, chamferRadius: 0), steel,
                                                     at: SCNVector3((tankX + target.x) / 2, target.y + 0.6, -0.4)))

        let ink = SCNMaterial()
        ink.lightingModel = .constant
        ink.diffuse.contents = UIColor(white: 0.07, alpha: 1)
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.09, pipeRadius: 0.016))
        ring.geometry?.materials = [ink]
        ring.eulerAngles.x = .pi / 2
        crosshair.addChildNode(ring)
        for (w, h) in [(0.26, 0.012), (0.012, 0.26)] as [(CGFloat, CGFloat)] {
            let bar = SCNNode(geometry: SCNBox(width: w, height: h, length: 0.01, chamferRadius: 0))
            bar.geometry?.materials = [ink]
            crosshair.addChildNode(bar)
        }
        crosshair.position = SCNVector3(target.x, target.y, target.z + 0.05)
        scene.rootNode.addChildNode(crosshair)
    }
}
