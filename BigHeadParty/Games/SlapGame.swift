import SceneKit
import SwiftUI
import simd

/// Main-thread delays that can all be cancelled at once (when a game ends or the view closes).
final class GameClock {
    private var generation = 0

    func after(_ seconds: Double, _ work: @escaping () -> Void) {
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.generation == g else { return }
            work()
        }
    }

    func cancelAll() { generation += 1 }
}

/// "Slap Champs": turn-based slap contest. Stop the needle in the gold zone; a perfect slap
/// plays in slow motion with a close-up of the cheek ripple.
final class SlapGame: ObservableObject {
    enum Phase: Equatable { case intro, aiming, slapping, finished }

    @Published var phase: Phase = .intro
    @Published var hp = [100, 100]
    @Published var turn = 0
    @Published var slapNumber = 0
    @Published var needle: Double = 0.5
    @Published var callout: String?
    @Published var resultLine = ""

    let totalSlaps = 6
    /// The gold zone is |needle − 0.5| < 0.075, i.e. power > 0.85.
    static let perfectZone = 0.15
    let players: [GameCharacter]
    let vsCPU: Bool
    let scene = SCNScene()
    let cameraRig = SCNNode()
    let camera = Effects.makeCamera(fov: 38)
    private(set) var contestants: [Contestant] = []
    weak var view: SCNView?

    private let clock = GameClock()
    private var needleTimer: Timer?
    private var needleTime = 0.0

    init(players: [GameCharacter], vsCPU: Bool) {
        self.players = players
        self.vsCPU = vsCPU
        buildSet()
        let facing = Float.pi / 2 - 0.62
        for i in 0..<2 {
            let c = Contestant(character: players[i], legs: .standing, headTurn: i == 0 ? -0.45 : 0.45)
            c.group.position = SCNVector3(i == 0 ? -0.8 : 0.8, 2.5, 0)
            c.group.eulerAngles.y = i == 0 ? facing : -facing
            scene.rootNode.addChildNode(c.group)
            c.rig.startIdle(seed: Double(i) * 1.7)
            contestants.append(c)
        }
        cameraRig.addChildNode(camera)
        scene.rootNode.addChildNode(cameraRig)
        wideShot(duration: 0)
    }

    var isHumanTurn: Bool { !(vsCPU && turn == 1) }

    func start() {
        phase = .intro
        callout = "SLAP CHAMPS"
        clock.after(1.4) { [weak self] in
            self?.callout = nil
            self?.nextTurn()
        }
    }

    func stop() {
        clock.cancelAll()
        needleTimer?.invalidate()
        scene.rootNode.speed = 1
    }

    func snapshot() -> UIImage? { view?.snapshot() }

    private func wideShot(duration: TimeInterval = 0.7) {
        let k = (contestants.first?.headScale ?? 0.55) / 0.55
        cameraRig.fly(to: SCNVector3(0, 2.5 + 1.1 * k, 4.6 + 2.2 * k), lookAt: SCNVector3(0, 2.2 + 0.6 * k, 0), duration: duration)
    }

    // MARK: - Turns

    private func nextTurn() {
        if slapNumber >= totalSlaps || hp.contains(where: { $0 <= 0 }) { return finish() }
        phase = .aiming
        wideShot()
        needleTime = Double.random(in: 0...3)
        let speed = 1.2 + Double(slapNumber) * 0.2
        needleTimer?.invalidate()
        needleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.needleTime += 1.0 / 60
            self.needle = 0.5 + 0.5 * sin(self.needleTime * speed * .pi)
        }
        if !isHumanTurn {
            clock.after(Double.random(in: 0.9...2.4)) { [weak self] in self?.slap() }
        }
    }

    /// Stops the needle and throws the slap.
    func slap() {
        guard phase == .aiming else { return }
        needleTimer?.invalidate()
        phase = .slapping
        perform(attacker: turn, power: 1 - abs(needle - 0.5) * 2)
    }

    private func perform(attacker ai: Int, power: Double) {
        let A = contestants[ai], D = contestants[1 - ai]
        // The arm on the camera side of each slapper.
        guard let arm = ai == 0 ? A.body?.armL : A.body?.armR, let parent = arm.parent else { return }
        let perfect = power > 1 - Self.perfectZone
        let damage = Int((6 + 28 * power * power).rounded())

        // Aim at the defender's cheek on the side facing the attacker.
        let face = D.rig.faceWorldPosition
        let toA = simd_normalize(simd_float3(A.group.simdPosition.x - D.group.simdPosition.x, 0, A.group.simdPosition.z - D.group.simdPosition.z))
        let cheek = simd_float3(face.x, face.y, face.z) + toA * (0.6 * D.headScale) + simd_float3(0, -0.1 * D.headScale, 0)
        let local = parent.simdConvertPosition(cheek, from: nil) - arm.simdPosition
        let stretch = simd_length(local) / 1.28           // arm reach at rest ≈ 1.28
        let qRest = arm.simdOrientation
        let qHit = simd_quaternion(simd_float3(0, -1, 0), simd_normalize(local))
        let qBack = simd_quatf(angle: ai == 0 ? -1.9 : 1.9, axis: simd_float3(0, 1, 0)) * qHit

        A.rig.pulse(.puff, peak: 0.4, attack: 0.15, hold: 0.25, release: 0.4)
        let wind = 0.45, strike = 0.12, follow = 0.14, back = 0.45
        var landed = false
        let cheekPoint = SCNVector3(cheek.x, cheek.y, cheek.z)
        arm.runAction(.customAction(duration: wind + strike + follow + back) { [weak self] node, elapsed in
            let t = Double(elapsed)
            if t < wind {
                let k = Float(t / wind)
                node.simdOrientation = simd_slerp(qRest, qBack, k * k * (3 - 2 * k))
            } else if t < wind + strike {
                let k = Float((t - wind) / strike)
                node.simdOrientation = simd_slerp(qBack, qHit, k * k)
                node.scale = SCNVector3(1, 1 + (stretch - 1) * k, 1)
            } else {
                if !landed {
                    landed = true
                    DispatchQueue.main.async { self?.impact(attacker: ai, power: power, damage: damage, at: cheekPoint, perfect: perfect) }
                }
                guard t >= wind + strike + follow else { return }   // the hand stays on the cheek for a beat
                let k = Float(min(1, (t - wind - strike - follow) / back))
                node.simdOrientation = simd_slerp(qHit, qRest, k * k * (3 - 2 * k))
                node.scale = SCNVector3(1, stretch + (1 - stretch) * k, 1)
            }
        })

        if perfect {
            clock.after(wind - 0.04) { [weak self] in
                guard let self else { return }
                self.scene.rootNode.speed = 0.18            // slow motion for everything in the scene
                let shot = D.closeUp(side: 0.6)
                self.cameraRig.fly(to: shot.position, lookAt: shot.target, duration: 0.5)
                self.callout = "PERFECT SLAP!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.scene.rootNode.speed = 1 }
            }
        }
    }

    private func impact(attacker ai: Int, power: Double, damage: Int, at point: SCNVector3, perfect: Bool) {
        let di = 1 - ai, D = contestants[di]
        let dir: Float = ai == 0 ? 1 : -1, pw = Float(power)
        D.rig.pulse(dir > 0 ? .skewRight : .skewLeft, peak: CGFloat(0.5 + 0.8 * power), attack: 0.03, hold: 0.15, release: 1.1)
        D.rig.pulse(.puff, peak: CGFloat(0.3 + 0.5 * power), attack: 0.03, hold: 0.1, release: 0.9)
        D.rig.pulse(.mouthOpen, peak: CGFloat(0.5 * power), attack: 0.05, hold: 0.1, release: 0.8)
        D.rig.wobbleHit(sideways: dir * (0.6 + pw), back: 0.25, strength: 0.8 + pw)
        Effects.burst(in: scene, at: point, color: UIColor(red: 0.75, green: 0.9, blue: 1, alpha: 1), count: CGFloat(30 + power * 70),
                      velocity: CGFloat(2.5 + power * 3), size: CGFloat(0.03 + 0.06 * D.headScale),
                      direction: SCNVector3(-dir, 0.4, 0.2), spread: 60, lifespan: 0.7)
        Effects.shake(camera, intensity: 0.05 + 0.12 * pw)
        Effects.haptic(power > 0.6 ? .heavy : .medium)
        hp[di] = max(0, hp[di] - damage)
        callout = perfect ? "PERFECT SLAP! −\(damage)"
            : power > 0.6 ? "Good slap! −\(damage)"
            : power > 0.3 ? "Meh. −\(damage)" : "A gentle pat. −\(damage)"

        clock.after(2.1) { [weak self] in
            guard let self else { return }
            self.callout = nil
            if self.hp[di] <= 0 {
                D.group.runAction(.group([.rotateBy(x: 0, y: 0, z: CGFloat(-dir * 1.45), duration: 0.7),
                                          .moveBy(x: 0, y: -0.9, z: 0, duration: 0.7)]))
                self.clock.after(0.9) { [weak self] in self?.finish() }
                return
            }
            self.slapNumber += 1
            self.turn = 1 - self.turn
            self.nextTurn()
        }
    }

    private func finish() {
        phase = .finished
        needleTimer?.invalidate()
        wideShot()
        if hp[0] == hp[1] {
            resultLine = "Dead even. Both cheeks are glowing."
            return
        }
        let w = hp[0] > hp[1] ? 0 : 1
        contestants[w].rig.pulse(.puff, peak: 0.8, attack: 0.1, hold: 0.4, release: 0.6)
        Effects.confetti(in: scene, at: SCNVector3(contestants[w].group.position.x, 4.6, 0.3))
        resultLine = "\(players[w].name) is the Slap Champ! " + (hp[1 - w] <= 0 ? "Knocked clean out." : "Won on cheek damage.")
    }

    // MARK: - Set

    private func buildSet() {
        scene.background.contents = UIColor(red: 0.07, green: 0.08, blue: 0.13, alpha: 1)
        Effects.addStudioLights(to: scene, rim: .systemPink)
        let floor = SCNFloor()
        floor.reflectivity = 0.05
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.09, green: 0.1, blue: 0.16, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
        scene.rootNode.addChildNode(Accessories.node(SCNCylinder(radius: 2.45, height: 0.1),
                                                     Accessories.material(UIColor(red: 0.66, green: 0.11, blue: 0.16, alpha: 1), roughness: 0.75),
                                                     at: SCNVector3(0, 0.05, 0)))
        scene.rootNode.addChildNode(Accessories.node(SCNPlane(width: 24, height: 12),
                                                     Accessories.material(UIColor(red: 0.07, green: 0.08, blue: 0.13, alpha: 1), roughness: 0.95),
                                                     at: SCNVector3(0, 5, -4.4)))
        let banner = SCNMaterial()
        banner.lightingModel = .constant
        banner.diffuse.contents = Effects.banner("SLAP CHAMPS", background: UIColor(red: 0.07, green: 0.08, blue: 0.13, alpha: 1))
        let bannerNode = SCNNode(geometry: SCNPlane(width: 8, height: 2))
        bannerNode.geometry?.materials = [banner]
        bannerNode.position = SCNVector3(0, 5.6, -4.3)
        scene.rootNode.addChildNode(bannerNode)
        scene.rootNode.addChildNode(Accessories.node(SCNBox(width: 0.42, height: 1.25, length: 0.8, chamferRadius: 0.03),
                                                     Accessories.material(UIColor(white: 0.17, alpha: 1), roughness: 0.35, metalness: 0.4),
                                                     at: SCNVector3(0, 0.72, -0.35)))
        let beam = SCNMaterial()
        beam.lightingModel = .constant
        beam.diffuse.contents = UIColor(red: 1, green: 0.95, blue: 0.77, alpha: 1)
        beam.transparency = 0.05
        beam.isDoubleSided = true
        beam.writesToDepthBuffer = false
        for sx: Float in [-1, 1] {
            let cone = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 1.5, height: 7))
            cone.geometry?.materials = [beam]
            cone.position = SCNVector3(sx * 0.9, 3.6, 0)
            scene.rootNode.addChildNode(cone)
        }
    }
}
