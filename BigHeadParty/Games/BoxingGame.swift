import SceneKit
import SwiftUI

enum Punch: CaseIterable {
    case jab, hook, uppercut

    var damage: Double {
        switch self { case .jab: return 5; case .hook: return 9; case .uppercut: return 14 }
    }
    var recovery: TimeInterval {
        switch self { case .jab: return 0.32; case .hook: return 0.5; case .uppercut: return 0.75 }
    }
    var label: String {
        switch self { case .jab: return "JAB"; case .hook: return "HOOK"; case .uppercut: return "UPPER" }
    }
}

/// One boxer: a big head on a small body with two gloves.
final class Fighter {
    let rig: HeadRig
    let root: SCNNode
    let gloves: [SCNNode]
    static let guardPositions: [SCNVector3] = [SCNVector3(-0.42, 1.95, 0.6), SCNVector3(0.42, 1.95, 0.6)]
    static let blockPositions: [SCNVector3] = [SCNVector3(-0.2, 2.55, 0.85), SCNVector3(0.2, 2.55, 0.85)]
    var guardPositions: [SCNVector3] { Fighter.guardPositions }
    var blockPositions: [SCNVector3] { Fighter.blockPositions }
    var hp: Double = 100
    var blocking = false
    var busyUntil = Date.distantPast

    init(character: GameCharacter, gloveColor: UIColor) {
        let rig = HeadRig(character: character)
        self.rig = rig
        let root = SCNNode()
        self.root = root
        let headScale: Float = 0.7
        rig.root.position = SCNVector3(0, 2.4, 0)
        rig.root.scale = SCNVector3(headScale, headScale, headScale)
        let skin = UIColor(rgb: character.meta.skinRGB)
        rig.root.addChildNode(Accessories.torso(color: UIColor(rgb: character.meta.shirtRGB), skin: skin))
        root.addChildNode(rig.root)

        let shorts = Accessories.material(gloveColor.darker(0.7), roughness: 0.6)
        let legs = Accessories.material(skin, roughness: 0.7)
        for x: Float in [-0.22, 0.22] {
            root.addChildNode(Accessories.node(SCNCapsule(capRadius: 0.17, height: 1.0), legs, at: SCNVector3(x, 0.6, 0)))
            root.addChildNode(Accessories.node(SCNBox(width: 0.36, height: 0.35, length: 0.42, chamferRadius: 0.1), shorts, at: SCNVector3(x, 1.2, 0)))
        }
        let gloveMat = Accessories.material(gloveColor, roughness: 0.3)
        gloves = Fighter.guardPositions.map { p in
            let g = Accessories.node(SCNSphere(radius: 0.27), gloveMat, at: p)
            g.scale = SCNVector3(1, 0.95, 1.15)
            return g
        }
        gloves.forEach(root.addChildNode)
        rig.startIdle(seed: Double.random(in: 0...6))
        // Boxer bounce.
        root.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.06, z: 0, duration: 0.28),
                                                 .moveBy(x: 0, y: -0.06, z: 0, duration: 0.28)])), forKey: "bounce")
    }

    var isBusy: Bool { Date() < busyUntil }

    func setBlocking(_ on: Bool) {
        blocking = on
        for (i, g) in gloves.enumerated() {
            g.removeAction(forKey: "guard")
            g.runAction(.move(to: on ? blockPositions[i] : guardPositions[i], duration: 0.08), forKey: "guard")
        }
    }

    /// Animates a punch toward a world-space point. Returns the time until impact.
    func throwPunch(_ punch: Punch, at worldTarget: SCNVector3) -> TimeInterval {
        let target = root.convertPosition(worldTarget, from: nil)
        let gi = punch == .jab ? 0 : 1
        let glove = gloves[gi]
        let rest = guardPositions[gi]
        let windup: TimeInterval = punch == .jab ? 0.05 : 0.1
        let strike: TimeInterval = punch == .uppercut ? 0.12 : 0.09
        var path: [SCNAction] = [.move(to: SCNVector3(rest.x, rest.y - (punch == .uppercut ? 0.45 : 0), rest.z - 0.2), duration: windup)]
        switch punch {
        case .jab:
            path.append(.move(to: target, duration: strike))
        case .hook:
            let mid = SCNVector3((rest.x + target.x) / 2 + 0.6, (rest.y + target.y) / 2, (rest.z + target.z) / 2)
            path.append(.move(to: mid, duration: strike * 0.5))
            path.append(.move(to: target, duration: strike * 0.5))
        case .uppercut:
            path.append(.move(to: SCNVector3(target.x, target.y - 0.25, target.z), duration: strike))
        }
        path.append(.wait(duration: 0.05))
        path.append(.move(to: blocking ? blockPositions[gi] : rest, duration: 0.18))
        glove.removeAction(forKey: "guard")
        glove.runAction(.sequence(path), forKey: "punch")
        // Lean into it.
        rig.wobbleHit(sideways: 0, back: -0.4, strength: 0.6)
        busyUntil = Date().addingTimeInterval(windup + strike + punch.recovery)
        return windup + strike
    }

    func knockedOut() {
        root.removeAction(forKey: "bounce")
        rig.spinOut()
        rig.setMorph(.mouthOpen, 1)
        root.runAction(.sequence([.wait(duration: 1.1),
                                  .group([.rotateBy(x: -1.45, y: 0, z: 0, duration: 0.45),
                                          .moveBy(x: 0, y: -0.2, z: -0.4, duration: 0.45)])]))
    }

    func celebrate() {
        root.removeAction(forKey: "bounce")
        for (i, g) in gloves.enumerated() {
            g.runAction(.repeatForever(.sequence([.move(to: SCNVector3(i == 0 ? -0.5 : 0.5, 3.4, 0.2), duration: 0.2),
                                                  .move(to: SCNVector3(i == 0 ? -0.45 : 0.45, 3.1, 0.2), duration: 0.2)])))
        }
        root.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.35, z: 0, duration: 0.2),
                                                 .moveBy(x: 0, y: -0.35, z: 0, duration: 0.25)])))
    }
}

/// "Bobble Boxing": tap to jab/hook/uppercut, hold to block. Heads wobble, faces squish.
final class BoxingGame: ObservableObject {
    enum Phase: Equatable { case intro, fighting, finished }

    @Published var phase: Phase = .intro
    @Published var hp: [Double] = [100, 100]
    @Published var timeLeft: Int = 60
    @Published var callout: String?
    @Published var combo = 0
    @Published var resultLine = ""

    let players: [GameCharacter]
    let vsCPU: Bool
    let scene = SCNScene()
    let cameraRig = SCNNode()
    let camera = Effects.makeCamera(fov: 40, horizontal: true)
    private(set) var fighters: [Fighter] = []
    weak var view: SCNView?

    private var generation = 0
    private var clock: Timer?

    init(players: [GameCharacter], vsCPU: Bool) {
        self.players = players
        self.vsCPU = vsCPU
        buildRing()
        let gloveColors: [UIColor] = [UIColor(red: 0.15, green: 0.4, blue: 0.95, alpha: 1), UIColor(red: 0.9, green: 0.12, blue: 0.12, alpha: 1)]
        for i in 0..<2 {
            let f = Fighter(character: players[i], gloveColor: gloveColors[i])
            // Face each other, but cheat toward the camera so both faces stay visible.
            let facing: Float = .pi / 2 - 0.7
            f.root.position = SCNVector3(i == 0 ? -1.25 : 1.25, 0.3, 0)
            f.root.eulerAngles.y = i == 0 ? facing : -facing
            f.rig.root.eulerAngles.y = i == 0 ? -0.3 : 0.3   // heads turn a bit more toward camera
            scene.rootNode.addChildNode(f.root)
            fighters.append(f)
        }
        cameraRig.addChildNode(camera)
        cameraRig.position = SCNVector3(0, 2.9, 8.2)
        cameraRig.look(at: SCNVector3(0, 2.2, 0))
        scene.rootNode.addChildNode(cameraRig)
    }

    private func buildRing() {
        scene.background.contents = UIColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)
        Effects.addStudioLights(to: scene, rim: UIColor(red: 0.3, green: 0.8, blue: 1, alpha: 1), fill: UIColor(red: 1, green: 0.85, blue: 0.7, alpha: 1))
        let floor = SCNFloor()
        floor.reflectivity = 0.05
        floor.firstMaterial?.diffuse.contents = UIColor(white: 0.08, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        let canvas = Accessories.node(SCNBox(width: 7.5, height: 0.3, length: 5, chamferRadius: 0.05),
                                      Accessories.material(UIColor(red: 0.85, green: 0.85, blue: 0.9, alpha: 1), roughness: 0.9),
                                      at: SCNVector3(0, 0.15, -0.5))
        scene.rootNode.addChildNode(canvas)
        let apron = Accessories.node(SCNBox(width: 7.6, height: 0.32, length: 5.1, chamferRadius: 0.02),
                                     Accessories.material(UIColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1)),
                                     at: SCNVector3(0, 0.14, -0.5))
        scene.rootNode.addChildNode(apron)

        let postMat = Accessories.material(UIColor(white: 0.85, alpha: 1), roughness: 0.3, metalness: 0.8)
        let corners: [(Float, Float)] = [(-3.6, -2.8), (3.6, -2.8), (-3.6, 1.8), (3.6, 1.8)]
        for (x, z) in corners {
            scene.rootNode.addChildNode(Accessories.node(SCNCylinder(radius: 0.08, height: 2.2), postMat, at: SCNVector3(x, 1.4, z)))
        }
        let ropeColors: [UIColor] = [.systemRed, .white, .systemBlue]
        for (k, color) in ropeColors.enumerated() {
            let y = Float(1.0 + 0.45 * Double(k))
            let mat = Accessories.material(color, roughness: 0.6)
            for z: Float in [-2.8] {   // back ropes only, so the camera has a clear view
                let rope = Accessories.node(SCNCylinder(radius: 0.035, height: 7.2), mat, at: SCNVector3(0, y, z))
                rope.eulerAngles.z = .pi / 2
                scene.rootNode.addChildNode(rope)
            }
            for x: Float in [-3.6, 3.6] {
                let rope = Accessories.node(SCNCylinder(radius: 0.035, height: 4.6), mat, at: SCNVector3(x, y, -0.5))
                rope.eulerAngles.x = .pi / 2
                scene.rootNode.addChildNode(rope)
            }
        }
        // Crowd flashbulbs.
        let flashMat = SCNMaterial()
        flashMat.lightingModel = .constant
        flashMat.diffuse.contents = UIColor.white
        for _ in 0..<40 {
            let bulb = Accessories.node(SCNSphere(radius: 0.05), flashMat,
                                        at: SCNVector3(Float.random(in: -9...9), Float.random(in: 1...5), Float.random(in: -9 ... -5)))
            bulb.opacity = 0
            bulb.runAction(.repeatForever(.sequence([.wait(duration: Double.random(in: 0.5...4)),
                                                     .fadeIn(duration: 0.03), .fadeOut(duration: 0.2)])))
            scene.rootNode.addChildNode(bulb)
        }
    }

    // MARK: - Flow

    func start() {
        generation += 1
        phase = .intro
        callout = "ROUND 1"
        after(1.2) { [weak self] in self?.callout = "FIGHT!" }
        after(2.0) { [weak self] in
            guard let self else { return }
            self.callout = nil
            self.phase = .fighting
            self.startClock()
            if self.vsCPU { self.scheduleAI() }
        }
    }

    func stop() {
        generation += 1
        clock?.invalidate()
    }

    func punch(_ punch: Punch, by attacker: Int) {
        guard phase == .fighting else { return }
        let me = fighters[attacker], them = fighters[1 - attacker]
        guard !me.isBusy else { return }
        if me.blocking { me.setBlocking(false) }
        let target = them.rig.faceWorldPosition
        let delay = me.throwPunch(punch, at: target)
        // AI sometimes reads the punch and covers up.
        if vsCPU && attacker == 0 && !them.isBusy && Double.random(in: 0...1) < 0.22 {
            them.setBlocking(true)
            after(0.6) { [weak self] in self?.fighters[1].setBlocking(false) }
        }
        after(delay) { [weak self] in self?.land(punch, attacker: attacker) }
    }

    func setBlocking(_ on: Bool, player: Int) {
        guard phase == .fighting, !fighters[player].isBusy || !on else { return }
        fighters[player].setBlocking(on)
    }

    private func land(_ punch: Punch, attacker: Int) {
        guard phase == .fighting else { return }
        let defender = 1 - attacker
        let them = fighters[defender]
        let face = them.rig.faceWorldPosition
        if them.blocking {
            hp[defender] = max(0, hp[defender] - punch.damage * 0.15)
            them.rig.wobbleHit(sideways: 0, back: 0.3, strength: 0.3)
            Effects.burst(in: scene, at: face, color: .white, count: 20, velocity: 2, size: 0.05, spread: 120, gravity: false, lifespan: 0.3)
            if attacker == 0 { combo = 0 }
            flash("BLOCKED")
            Effects.haptic(.light)
            return
        }
        hp[defender] = max(0, hp[defender] - punch.damage)
        let away: Float = attacker == 0 ? 1 : -1
        switch punch {
        case .jab:
            them.rig.wobbleHit(sideways: away * 0.2, back: 0.8, strength: 0.8)
            them.rig.pulse(.squish, peak: 0.55, hold: 0.06, release: 0.5)
        case .hook:
            them.rig.wobbleHit(sideways: away, back: 0.2, strength: 1.1)
            them.rig.pulse(attacker == 0 ? .skewRight : .skewLeft, peak: 1, hold: 0.1, release: 0.7)
            them.rig.pulse(.puff, peak: 0.5, hold: 0.05, release: 0.5)
        case .uppercut:
            them.rig.wobbleHit(sideways: away * 0.3, back: 1.5, strength: 1.4)
            them.rig.pulse(.mouthOpen, peak: 1, hold: 0.15, release: 0.8)
            them.rig.pulse(.squish, peak: 0.6, hold: 0.1, release: 0.6)
        }
        Effects.burst(in: scene, at: face, color: .systemYellow, count: punch == .jab ? 8 : 16, velocity: 2.5, size: 0.16,
                      image: Effects.starImage, spread: 180, gravity: false, lifespan: 0.7)
        Effects.burst(in: scene, at: face, color: UIColor(red: 0.7, green: 0.9, blue: 1, alpha: 1), count: 25, velocity: 3,
                      size: 0.05, direction: SCNVector3(away, 0.5, 0), spread: 40, lifespan: 0.6)   // sweat
        Effects.shake(camera, intensity: punch == .uppercut ? 0.18 : 0.08, duration: 0.3)
        Effects.haptic(punch == .jab ? .medium : .heavy)

        if attacker == 0 {
            combo += 1
            if combo >= 3 { flash("\(combo) HIT COMBO!") }
        } else {
            combo = 0
        }
        if punch == .uppercut { flash(["BOOM!", "POW!", "OOF!", "SAY GOODNIGHT!"].randomElement()!) }
        if hp[defender] <= 0 { knockout(loser: defender) }
    }

    private func knockout(loser: Int) {
        phase = .finished
        clock?.invalidate()
        fighters[loser].knockedOut()
        fighters[1 - loser].celebrate()
        callout = "K.O.!"
        resultLine = "\(players[1 - loser].name) knocks out \(players[loser].name)!"
        Effects.confetti(in: scene, at: SCNVector3(fighters[1 - loser].root.position.x, 4.5, 0))
        zoom(on: loser)
    }

    private func decision() {
        phase = .finished
        if hp[0] == hp[1] {
            callout = "DRAW!"
            resultLine = "Nobody wins. Everybody's face hurts."
            return
        }
        let w = hp[0] > hp[1] ? 0 : 1
        callout = "DECISION"
        resultLine = "\(players[w].name) wins on points!"
        fighters[w].celebrate()
        Effects.confetti(in: scene, at: SCNVector3(fighters[w].root.position.x, 4.5, 0))
    }

    private func zoom(on index: Int) {
        let face = fighters[index].rig.faceWorldPosition
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.9
        cameraRig.position = SCNVector3(face.x * 0.6, face.y + 0.3, 5)
        cameraRig.look(at: face)
        SCNTransaction.commit()
    }

    func snapshot() -> UIImage? { view?.snapshot() }

    // MARK: - CPU

    private func scheduleAI() {
        after(Double.random(in: 0.45...1.2)) { [weak self] in
            guard let self, self.phase == .fighting else { return }
            let cpu = self.fighters[1]
            let roll = Double.random(in: 0...1)
            if roll < 0.62 {
                let p: Punch = {
                    let r = Double.random(in: 0...1)
                    return r < 0.5 ? .jab : (r < 0.8 ? .hook : .uppercut)
                }()
                self.punch(p, by: 1)
            } else if roll < 0.78 && !cpu.isBusy {
                cpu.setBlocking(true)
                self.after(Double.random(in: 0.5...1.0)) { [weak self] in self?.fighters[1].setBlocking(false) }
            }
            self.scheduleAI()
        }
    }

    // MARK: - Timing

    private func startClock() {
        timeLeft = 60
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self, self.phase == .fighting else { t.invalidate(); return }
            self.timeLeft -= 1
            if self.timeLeft <= 0 {
                t.invalidate()
                self.decision()
            }
        }
    }

    private func flash(_ text: String) {
        callout = text
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.generation == gen, self.callout == text, self.phase == .fighting else { return }
            self.callout = nil
        }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.generation == gen else { return }
            work()
        }
    }
}
