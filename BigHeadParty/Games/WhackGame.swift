import SceneKit
import SwiftUI

/// "Whack-a-Head": faces pop out of a 3×3 board. Tap to bonk. Golden heads are worth 3,
/// bonking the baby costs 2. Your own face pops up most often. 30 seconds.
final class WhackGame: ObservableObject {
    final class Mole {
        let contestant: Contestant
        var hole = -1
        var hit = false
        var golden = false
        init(_ c: Contestant) { contestant = c }
    }

    @Published var score = 0
    @Published var timeLeft = 30
    @Published var best: Int
    @Published var callout: String?
    @Published var finished = false

    static let bestKey = "whackBest"
    let player: GameCharacter
    let scene = SCNScene()
    let cameraRig = SCNNode()
    let camera = Effects.makeCamera(fov: 38)
    weak var view: SCNView?

    private var moles: [Mole] = []
    private let holes: [SCNVector3] = [-1.15, 0, 1.15].flatMap { z in [-1.4, 0, 1.4].map { x in SCNVector3(Float(x), 0, Float(z)) } }
    private let upY: Float = 0.95, downY: Float = -0.25, headScale: Float = 0.36
    private let clock = GameClock()

    init(player: GameCharacter, cast: [GameCharacter]) {
        self.player = player
        best = UserDefaults.standard.integer(forKey: Self.bestKey)
        buildSet()
        let others = cast.filter { $0.id != player.id }
        for character in ([player] + others).prefix(5) {
            let c = Contestant(character: character, headScale: headScale, withBody: false)
            c.group.eulerAngles.x = -0.35
            c.group.position = SCNVector3(0, downY, 0)
            c.group.isHidden = true
            c.rig.startIdle(seed: Double.random(in: 0...6))
            scene.rootNode.addChildNode(c.group)
            moles.append(Mole(c))
        }
        cameraRig.addChildNode(camera)
        cameraRig.position = SCNVector3(0, 5.4, 5.2)
        cameraRig.look(at: SCNVector3(0, 0.9, 0.25))
        scene.rootNode.addChildNode(cameraRig)
    }

    func start() {
        callout = "Get ready…"
        clock.after(1.2) { [weak self] in
            guard let self else { return }
            self.callout = "GO!"
            self.pop()
            self.tick()
            self.clock.after(0.7) { [weak self] in if self?.callout == "GO!" { self?.callout = nil } }
        }
    }

    func stop() { clock.cancelAll() }

    func snapshot() -> UIImage? { view?.snapshot() }

    // MARK: - Loop

    private func tick() {
        guard timeLeft > 0 else { return }
        clock.after(1) { [weak self] in
            guard let self else { return }
            self.timeLeft -= 1
            if self.timeLeft <= 0 { self.finish() } else { self.tick() }
        }
    }

    private func pop() {
        guard timeLeft > 0 else { return }
        let free = holes.indices.filter { i in !moles.contains { $0.hole == i } }
        let idle = moles.filter { $0.hole < 0 }
        if let h = free.randomElement(), !idle.isEmpty {
            // The player's own face shows up most.
            let mole = (moles[0].hole < 0 && Double.random(in: 0...1) < 0.4) ? moles[0] : idle.randomElement()!
            mole.hole = h
            mole.hit = false
            mole.golden = Double.random(in: 0...1) < 0.13 && !isBaby(mole)
            mole.contestant.rig.setGolden(mole.golden)
            let g = mole.contestant.group
            g.position = SCNVector3(holes[h].x, downY, holes[h].z)
            g.isHidden = false
            let stay = max(0.5, 1.3 - Double(30 - timeLeft) * 0.027)
            g.runAction(.move(to: SCNVector3(holes[h].x, upY, holes[h].z), duration: 0.13))
            clock.after(0.13 + stay) { [weak self] in
                if !mole.hit && mole.hole == h { self?.retract(mole) }
            }
        }
        clock.after(Double.random(in: 0.26...0.62)) { [weak self] in self?.pop() }
    }

    private func retract(_ mole: Mole, duration: TimeInterval = 0.14) {
        let g = mole.contestant.group
        g.runAction(.move(to: SCNVector3(g.position.x, downY, g.position.z), duration: duration)) {
            DispatchQueue.main.async {
                mole.hole = -1
                g.isHidden = true
            }
        }
    }

    private func isBaby(_ mole: Mole) -> Bool {
        mole.contestant.character.name == "Baby Benny" && mole !== moles[0]
    }

    // MARK: - Tapping

    /// Generous screen-space hit test: the nearest live face within about a head's radius.
    func handleTap(at point: CGPoint, in view: SCNView) {
        guard timeLeft > 0, callout != "Get ready…" else { return }
        var nearest: (mole: Mole, distance: CGFloat)?
        for mole in moles where mole.hole >= 0 && !mole.hit {
            let rig = mole.contestant.rig
            let center = rig.faceWorldPosition
            let edge = rig.head.convertPosition(SCNVector3(1.1, rig.anchors.eyeY - 0.25, 1.1), to: nil)
            let c = view.projectPoint(center), e = view.projectPoint(edge)
            let radius = max(30, hypot(CGFloat(e.x - c.x), CGFloat(e.y - c.y)) * 1.2)
            let d = hypot(point.x - CGFloat(c.x), point.y - CGFloat(c.y))
            if d < radius, d < (nearest?.distance ?? .infinity) { nearest = (mole, d) }
        }
        guard let hit = nearest else {
            callout = "Whiff!"
            return
        }
        bonk(hit.mole)
    }

    private func bonk(_ mole: Mole) {
        mole.hit = true
        let baby = isBaby(mole)
        let points = baby ? -2 : (mole.golden ? 3 : 1)
        score = max(0, score + points)
        let rig = mole.contestant.rig
        let face = rig.faceWorldPosition
        rig.pulse(.squish, peak: 1, attack: 0.03, hold: 0.15, release: 0.6)
        rig.wobbleHit(sideways: Float.random(in: -0.5...0.5), back: 1)
        Effects.burst(in: scene, at: face, color: baby ? .systemPink : (mole.golden ? .systemYellow : .white), count: 22, velocity: 2.4,
                      size: 0.13, image: Effects.starImage, direction: SCNVector3(0, 1, 0.3), spread: 120, gravity: false, lifespan: 0.6)
        swingHammer(at: face)
        Effects.shake(camera, intensity: 0.05, duration: 0.2)
        Effects.haptic(baby ? .rigid : .medium)
        callout = baby ? "Not the baby! −2" : (mole.golden ? "GOLDEN BONK! +3" : ["Bonk!", "Boop!", "Gotcha!", "Thwack!"].randomElement()!)
        clock.after(0.28) { [weak self] in self?.retract(mole, duration: 0.1) }
    }

    private func swingHammer(at p: SCNVector3) {
        let hammer = SCNNode(), pivot = SCNNode()
        pivot.addChildNode(Accessories.node(SCNCylinder(radius: 0.05, height: 1.3), Accessories.material(UIColor(red: 0.77, green: 0.6, blue: 0.42, alpha: 1), roughness: 0.6),
                                            at: SCNVector3(0, 0.65, 0)))
        let head = Accessories.node(SCNCylinder(radius: 0.24, height: 0.6), Accessories.material(UIColor(red: 0.91, green: 0.2, blue: 0.31, alpha: 1), roughness: 0.5),
                                    at: SCNVector3(0, 1.35, 0))
        head.eulerAngles.z = .pi / 2
        pivot.addChildNode(head)
        hammer.addChildNode(pivot)
        hammer.position = SCNVector3(p.x + 0.2, p.y - 0.9, p.z + 1.1)
        pivot.eulerAngles.x = 0.6
        scene.rootNode.addChildNode(hammer)
        pivot.runAction(.rotateTo(x: -0.75, y: 0, z: 0, duration: 0.16)) {
            hammer.runAction(.sequence([.wait(duration: 0.22), .removeFromParentNode()]))
        }
    }

    private func finish() {
        finished = true
        callout = nil
        if score > best {
            best = score
            UserDefaults.standard.set(score, forKey: Self.bestKey)
        }
    }

    // MARK: - Set

    private func buildSet() {
        scene.background.contents = UIColor(red: 0.11, green: 0.08, blue: 0.15, alpha: 1)
        Effects.addStudioLights(to: scene, rim: .systemTeal)
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.11, green: 0.08, blue: 0.15, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
        let back = SCNMaterial()
        back.diffuse.contents = Effects.stripes(UIColor(red: 0.16, green: 0.5, blue: 0.83, alpha: 1), UIColor(red: 1, green: 0.81, blue: 0.29, alpha: 1), count: 20)
        let backNode = SCNNode(geometry: SCNPlane(width: 18, height: 8))
        backNode.geometry?.materials = [back]
        backNode.position = SCNVector3(0, 3.5, -3.4)
        scene.rootNode.addChildNode(backNode)

        // Board with nine holes (even-odd fill punches them out).
        let path = UIBezierPath(rect: CGRect(x: -2.3, y: -1.95, width: 4.6, height: 3.9))
        for h in holes { path.append(UIBezierPath(ovalIn: CGRect(x: CGFloat(h.x) - 0.5, y: CGFloat(-h.z) - 0.5, width: 1, height: 1))) }
        path.usesEvenOddFillRule = true
        path.flatness = 0.005
        let board = SCNShape(path: path, extrusionDepth: 0.12)
        board.chamferRadius = 0.02
        let boardNode = SCNNode(geometry: board)
        boardNode.geometry?.materials = [Accessories.material(UIColor(red: 0.18, green: 0.56, blue: 0.36, alpha: 1), roughness: 0.55)]
        boardNode.eulerAngles.x = -.pi / 2
        boardNode.position = SCNVector3(0, 0.94, 0)
        scene.rootNode.addChildNode(boardNode)
        let rimM = Accessories.material(UIColor(white: 0.1, alpha: 1), roughness: 0.4)
        for h in holes {
            scene.rootNode.addChildNode(Accessories.node(SCNTorus(ringRadius: 0.5, pipeRadius: 0.05), rimM, at: SCNVector3(h.x, 1.02, h.z)))
        }
        let inside = Accessories.material(UIColor(red: 0.05, green: 0.04, blue: 0.07, alpha: 1), roughness: 1)
        scene.rootNode.addChildNode(Accessories.node(SCNBox(width: 4.6, height: 0.05, length: 3.9, chamferRadius: 0), inside, at: SCNVector3(0, -0.6, 0)))
        let wall = Accessories.material(UIColor(red: 0.85, green: 0.16, blue: 0.25, alpha: 1), roughness: 0.6)
        for (x, z, w, d) in [(0, 1.95, 4.6, 0.1), (0, -1.95, 4.6, 0.1), (-2.3, 0, 0.1, 3.9), (2.3, 0, 0.1, 3.9)] as [(Float, Float, CGFloat, CGFloat)] {
            scene.rootNode.addChildNode(Accessories.node(SCNBox(width: w, height: 1.6, length: d, chamferRadius: 0), wall, at: SCNVector3(x, 0.1, z)))
        }
    }
}
