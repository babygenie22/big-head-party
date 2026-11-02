import SceneKit
import simd
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
            popUp(mole, at: holes[h])
            #if DEBUG
            // `-whackAutoBonk YES` hits every head, for checking the hit animation in the simulator.
            if UserDefaults.standard.bool(forKey: "whackAutoBonk") {
                clock.after(0.45) { [weak self] in if !mole.hit && mole.hole == h { self?.bonk(mole) } }
            }
            #endif
            clock.after(0.13 + stay) { [weak self] in
                if !mole.hit && mole.hole == h { self?.retract(mole) }
            }
        }
        clock.after(Double.random(in: 0.26...0.62)) { [weak self] in self?.pop() }
    }

    /// Springs out of the hole: stretched on the way up, overshoots, squashes on landing, then
    /// taunts (a peek, a raspberry, a look around) while it waits.
    private func popUp(_ mole: Mole, at hole: SCNVector3) {
        let g = mole.contestant.group, rig = mole.contestant.rig
        g.removeAllActions()
        g.scale = SCNVector3(0.85, 1.2, 0.85)
        let rise = SCNAction.move(to: SCNVector3(hole.x, upY + 0.16, hole.z), duration: 0.12)
        rise.timingMode = .easeOut
        let settle = SCNAction.move(to: SCNVector3(hole.x, upY, hole.z), duration: 0.1)
        settle.timingMode = .easeIn
        g.runAction(.sequence([rise, settle]))
        g.runAction(.sequence([.wait(duration: 0.12), Self.scale(to: SCNVector3(1.12, 0.86, 1.12), duration: 0.08),
                               Self.scale(to: SCNVector3(0.97, 1.04, 0.97), duration: 0.08), Self.scale(to: SCNVector3(1, 1, 1), duration: 0.08)]),
                    forKey: "squash")
        rig.wobbleHit(sideways: Float.random(in: -0.3...0.3), back: -0.25, strength: 0.6)
        clock.after(0.25) {
            guard !mole.hit else { return }
            switch Int.random(in: 0..<4) {
            case 0: rig.pulse(.mouthOpen, peak: 0.8, attack: 0.08, hold: 0.25, release: 0.4)             // "Boo!"
            case 1: rig.pulse(Bool.random() ? .skewLeft : .skewRight, peak: 0.7, hold: 0.3, release: 0.4) // raspberry
            case 2: rig.pulse(.puff, peak: 0.8, attack: 0.1, hold: 0.3, release: 0.4)                     // cheeks puffed
            default:                                                                                       // look around
                rig.root.runAction(.sequence([.rotateTo(x: 0, y: 0.5, z: 0, duration: 0.15), .wait(duration: 0.15),
                                              .rotateTo(x: 0, y: -0.5, z: 0, duration: 0.2), .wait(duration: 0.15),
                                              .rotateTo(x: 0, y: 0, z: 0, duration: 0.15)]), forKey: "look")
            }
        }
        if mole.golden { rig.root.runAction(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.35), forKey: "look") }
    }

    /// Squash-and-stretch: eases a node's (non-uniform) scale to `s`.
    private static func scale(to s: SCNVector3, duration: TimeInterval) -> SCNAction {
        var from: SCNVector3?
        return .customAction(duration: duration) { node, t in
            if from == nil { from = node.scale }
            guard let f = from else { return }
            let p = Float(t / CGFloat(max(duration, 0.001)))
            let e = p * p * (3 - 2 * p)
            node.scale = SCNVector3(f.x + (s.x - f.x) * e, f.y + (s.y - f.y) * e, f.z + (s.z - f.z) * e)
        }
    }

    private func retract(_ mole: Mole, duration: TimeInterval = 0.14) {
        let g = mole.contestant.group
        mole.contestant.rig.root.removeAction(forKey: "look")
        mole.contestant.rig.root.eulerAngles = SCNVector3Zero
        g.runAction(.sequence([Self.scale(to: SCNVector3(1.1, 0.88, 1.1), duration: 0.05), Self.scale(to: SCNVector3(0.9, 1.15, 0.9), duration: 0.05)]),
                    forKey: "squash")
        g.runAction(.move(to: SCNVector3(g.position.x, downY, g.position.z), duration: duration)) {
            DispatchQueue.main.async {
                mole.hole = -1
                g.isHidden = true
                g.scale = SCNVector3(1, 1, 1)
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
        rig.root.removeAction(forKey: "look")
        rig.root.eulerAngles = SCNVector3Zero
        rig.pulse(.mouthOpen, peak: 0.6, attack: 0.08, hold: 0.05, release: 0.2)   // sees it coming
        let crown = rig.head.convertPosition(SCNVector3(0, 1.28, 0), to: nil)
        swingHammer(onto: crown, golden: mole.golden)
        // The comic sticker says "BONK!"; the banner only calls out the special heads.
        callout = baby ? "Not the baby! −2" : (mole.golden ? "Golden! +3" : nil)
        clock.after(Self.strikeTime) { [weak self] in self?.impact(mole, baby: baby) }
        clock.after(Self.strikeTime + 0.75) { [weak self] in self?.retract(mole, duration: 0.12) }
    }

    /// Wind-up plus strike: when the hammer face meets the crown.
    private static let strikeTime: TimeInterval = 0.17

    private func impact(_ mole: Mole, baby: Bool) {
        let rig = mole.contestant.rig, g = mole.contestant.group
        let face = rig.faceWorldPosition
        // Pancake: squashed flat into the hole, then springs back.
        g.runAction(.sequence([Self.scale(to: SCNVector3(1.3, 0.55, 1.3), duration: 0.04), .wait(duration: 0.08),
                               Self.scale(to: SCNVector3(0.92, 1.12, 0.92), duration: 0.1), Self.scale(to: SCNVector3(1.04, 0.97, 1.04), duration: 0.08),
                               Self.scale(to: SCNVector3(1, 1, 1), duration: 0.08)]), forKey: "squash")
        g.runAction(.sequence([.moveBy(x: 0, y: -0.22, z: 0, duration: 0.04), .wait(duration: 0.1), .moveBy(x: 0, y: 0.22, z: 0, duration: 0.14)]))
        rig.pulse(.squish, peak: 1, attack: 0.03, hold: 0.15, release: 0.6)
        // A different reaction each time.
        switch Int.random(in: 0..<3) {
        case 0:
            rig.wobbleHit(sideways: Float.random(in: -0.6...0.6), back: 1)
            dizzyStars(over: rig)
        case 1:
            rig.spinOut()
            rig.pulse(.mouthOpen, peak: 1, attack: 0.05, hold: 0.3, release: 0.4)
        default:
            rig.wobbleHit(sideways: Bool.random() ? 1 : -1, back: 0.3, strength: 1.3)
            rig.pulse(Bool.random() ? .skewLeft : .skewRight, peak: 1, hold: 0.25, release: 0.5)
            dizzyStars(over: rig)
        }
        let color: UIColor = baby ? .systemPink : (mole.golden ? .systemYellow : .white)
        Effects.burst(in: scene, at: face, color: color, count: 26, velocity: 2.8,
                      size: 0.14, image: Effects.starImage, direction: SCNVector3(0, 1, 0.3), spread: 140, gravity: false, lifespan: 0.6)
        shockwave(at: SCNVector3(g.position.x, 1.06, g.position.z), color: mole.golden ? CandySet.butter : .white)
        comicPop(baby ? "WAH!" : (mole.golden ? "KA-CHING!" : ["BONK!", "BOP!", "THWACK!", "POW!"].randomElement()!),
                 at: SCNVector3(face.x + 0.35, face.y + 0.55, face.z + 0.3), fill: baby ? CandySet.bubblegum : (mole.golden ? CandySet.butter : CandySet.coral))
        Effects.shake(camera, intensity: 0.07, duration: 0.22)
        Effects.haptic(baby ? .rigid : .medium)
    }

    /// A squeaky toy mallet that comes down from the front right, flat face onto the crown.
    private func swingHammer(onto crown: SCNVector3, golden: Bool) {
        let model = RealBody.prop("mallet")
        let yaw: Float = 0.35, reach: Float = model == nil ? 1.5 : 0.85
        let hammer = SCNNode(), pivot = SCNNode()
        hammer.position = SCNVector3(crown.x + reach * sin(yaw), crown.y + (model == nil ? 0.2 : 0.3), crown.z + reach * cos(yaw))
        hammer.eulerAngles.y = yaw
        let mallet = SCNNode()
        mallet.position = SCNVector3(0, 0, -reach)
        if let model {
            // The realistic mallet: its handle (model +X, tilted) turned to run back to the hand
            // along +Z, barrel centred at the strike point.
            let s: Float = 1.2
            let handle = simd_normalize(simd_float3(0.945, -0.285, -0.159)), barrel = simd_float3(-0.208, -0.026, 0.028)
            let q = simd_quatf(from: handle, to: simd_float3(0, 0, 1))
            model.scale = SCNVector3(s, s, s)
            model.simdOrientation = q
            model.simdPosition = -q.act(barrel * s)
            if golden { model.enumerateHierarchy { n, _ in n.geometry?.firstMaterial?.multiply.contents = CandySet.butter } }
            mallet.addChildNode(model)
        } else {
            // Handle runs from the pivot (the hand) towards −z; the head sits across its end.
            let wood = Accessories.material(UIColor(red: 0.86, green: 0.66, blue: 0.44, alpha: 1), roughness: 0.55)
            let handle = Accessories.node(SCNCylinder(radius: 0.055, height: CGFloat(reach)), wood, at: SCNVector3(0, 0, -reach / 2))
            handle.eulerAngles.x = .pi / 2
            pivot.addChildNode(handle)
            let grip = Accessories.node(SCNCylinder(radius: 0.075, height: 0.4), Fabric.cloth(CandySet.ink, repeats: 6), at: SCNVector3(0, 0, -0.2))
            grip.eulerAngles.x = .pi / 2
            pivot.addChildNode(grip)
            let headColor = golden ? CandySet.butter : CandySet.coral
            mallet.addChildNode(Accessories.node(SCNCylinder(radius: 0.28, height: 0.5), Fabric.glossy(headColor, roughness: 0.3), at: SCNVector3(0, 0, 0)))
            for y: Float in [-0.25, 0.25] {
                let cap = SCNCylinder(radius: 0.3, height: 0.08)
                cap.radialSegmentCount = 48
                mallet.addChildNode(Accessories.node(cap, Fabric.glossy(.white, roughness: 0.3), at: SCNVector3(0, y, 0)))
            }
            mallet.addChildNode(Accessories.node(SCNTorus(ringRadius: 0.285, pipeRadius: 0.025), Fabric.glossy(.white), at: SCNVector3(0, 0, 0)))
        }
        pivot.addChildNode(mallet)
        hammer.addChildNode(pivot)
        hammer.enumerateHierarchy { n, _ in n.castsShadow = true }
        scene.rootNode.addChildNode(hammer)

        // Raised high, a short extra wind-up, then down; bounce off the head and lift away.
        pivot.eulerAngles.x = 1.0
        hammer.opacity = 0
        let windUp = SCNAction.rotateTo(x: 1.35, y: 0, z: 0, duration: 0.09)
        windUp.timingMode = .easeOut
        let strike = SCNAction.rotateTo(x: -0.02, y: 0, z: 0, duration: Self.strikeTime - 0.09)
        strike.timingMode = .easeIn
        let rebound = SCNAction.rotateTo(x: 0.3, y: 0, z: 0, duration: 0.08)
        rebound.timingMode = .easeOut
        let tap = SCNAction.rotateTo(x: 0.12, y: 0, z: 0, duration: 0.07)
        hammer.runAction(.fadeIn(duration: 0.05))
        // The mallet squashes a touch on contact.
        mallet.runAction(.sequence([.wait(duration: Self.strikeTime), Self.scale(to: SCNVector3(1.12, 0.82, 1.12), duration: 0.04), Self.scale(to: SCNVector3(1, 1, 1), duration: 0.1)]))
        pivot.runAction(.sequence([windUp, strike, rebound, tap, .wait(duration: 0.1), .rotateTo(x: 1.2, y: 0, z: 0, duration: 0.2)]))
        hammer.runAction(.sequence([.wait(duration: Self.strikeTime + 0.35), .fadeOut(duration: 0.18), .removeFromParentNode()]))
    }

    /// Three little stars that circle the crown for a moment.
    private func dizzyStars(over rig: HeadRig) {
        let ring = SCNNode()
        ring.position = SCNVector3(0, 1.55, 0)
        for i in 0..<3 {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = Effects.starImage
            m.multiply.contents = CandySet.butter
            m.writesToDepthBuffer = false
            let star = Accessories.node(SCNPlane(width: 0.45, height: 0.45), m, at: SCNVector3(0, 0, 0))
            let a = Float(i) / 3 * 2 * .pi
            star.position = SCNVector3(0.85 * cos(a), 0, 0.85 * sin(a))
            star.constraints = [SCNBillboardConstraint()]
            ring.addChildNode(star)
        }
        rig.root.addChildNode(ring)
        ring.runAction(.sequence([.group([.rotateBy(x: 0, y: .pi * 3, z: 0, duration: 0.8),
                                          .sequence([.wait(duration: 0.55), .fadeOut(duration: 0.25)])]),
                                  .removeFromParentNode()]))
    }

    /// A flat ring that rushes out across the board from the hole.
    private func shockwave(at p: SCNVector3, color: UIColor) {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.writesToDepthBuffer = false
        let wave = Accessories.node(SCNTorus(ringRadius: 0.55, pipeRadius: 0.04), m, at: p)
        scene.rootNode.addChildNode(wave)
        wave.runAction(.sequence([.group([.scale(to: 2.2, duration: 0.35), .fadeOut(duration: 0.35)]), .removeFromParentNode()]))
    }

    /// A comic-book sticker ("BONK!") that pops in, tilts, and floats away.
    private func comicPop(_ text: String, at p: SCNVector3, fill: UIColor) {
        let size = CGSize(width: 512, height: 300)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            // Spiky burst behind the word.
            let c = CGPoint(x: 256, y: 150), spikes = 14
            let burst = UIBezierPath()
            for i in 0..<(spikes * 2) {
                let a = CGFloat(i) / CGFloat(spikes * 2) * 2 * .pi
                let r: CGFloat = i % 2 == 0 ? 1 : 0.72
                let pt = CGPoint(x: c.x + cos(a) * 240 * r, y: c.y + sin(a) * 140 * r)
                i == 0 ? burst.move(to: pt) : burst.addLine(to: pt)
            }
            burst.close()
            CandySet.ink.setFill(); burst.fill()
            ctx.cgContext.translateBy(x: c.x, y: c.y); ctx.cgContext.scaleBy(x: 0.9, y: 0.88); ctx.cgContext.translateBy(x: -c.x, y: -c.y)
            fill.setFill(); burst.fill()
            ctx.cgContext.resetClip()
            ctx.cgContext.translateBy(x: c.x, y: c.y); ctx.cgContext.scaleBy(x: 1 / 0.9, y: 1 / 0.88); ctx.cgContext.translateBy(x: -c.x, y: -c.y)
            let fontSize: CGFloat = text.count > 6 ? 78 : 104
            let font = UIFont(name: "BricolageGrotesque-96ptExtraBold", size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .black)
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: style,
                                                        .strokeColor: CandySet.ink, .strokeWidth: -6]
            let h = (text as NSString).size(withAttributes: attrs).height
            (text as NSString).draw(in: CGRect(x: 0, y: c.y - h / 2, width: 512, height: h), withAttributes: attrs)
        }
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        let plane = Accessories.node(SCNPlane(width: 1.3, height: 1.3 * size.height / size.width), m, at: p)
        plane.renderingOrder = 100
        let holder = SCNNode()
        holder.constraints = [SCNBillboardConstraint()]
        holder.position = p
        plane.position = SCNVector3Zero
        plane.eulerAngles.z = Float.random(in: -0.25...0.25)
        holder.addChildNode(plane)
        holder.scale = SCNVector3(0.2, 0.2, 0.2)
        scene.rootNode.addChildNode(holder)
        let pop = SCNAction.scale(to: 1.15, duration: 0.09); pop.timingMode = .easeOut
        holder.runAction(.sequence([pop, .scale(to: 1, duration: 0.06), .wait(duration: 0.25),
                                    .group([.moveBy(x: 0, y: 0.35, z: 0, duration: 0.3), .fadeOut(duration: 0.3)]),
                                    .removeFromParentNode()]))
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
        scene.background.contents = CandySet.backdrop(CandySet.lilac, CandySet.cream)
        CandySet.light(scene, rim: CandySet.lilac, camera: camera)
        scene.rootNode.addChildNode(CandySet.floor(UIColor(red: 0.62, green: 0.52, blue: 0.92, alpha: 1)))
        let back = SCNMaterial()
        back.diffuse.contents = CandySet.stripes(CandySet.lilac, CandySet.cream, count: 16)
        back.lightingModel = .constant   // backdrop in true colors
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
        boardNode.geometry?.materials = [Accessories.material(CandySet.lime, roughness: 0.6)]
        boardNode.eulerAngles.x = -.pi / 2
        boardNode.position = SCNVector3(0, 0.94, 0)
        scene.rootNode.addChildNode(boardNode)
        // Each hole: a deep dark tunnel, a candy ring plate with bolts, and a glossy rolled rim.
        let rimM = Fabric.glossy(.white, roughness: 0.3)
        let tunnel = Accessories.material(UIColor(red: 0.16, green: 0.09, blue: 0.2, alpha: 1), roughness: 1)
        tunnel.isDoubleSided = true
        let pit = Accessories.material(UIColor(red: 0.07, green: 0.04, blue: 0.09, alpha: 1), roughness: 1)
        let plates = [CandySet.coral, CandySet.sky, CandySet.butter].map { Fabric.glossy($0, roughness: 0.4) }
        let bolt = Accessories.material(UIColor(white: 0.92, alpha: 1), roughness: 0.25, metalness: 0.6)
        for (i, h) in holes.enumerated() {
            scene.rootNode.addChildNode(Accessories.node(SCNTube(innerRadius: 0.47, outerRadius: 0.5, height: 1.5), tunnel, at: SCNVector3(h.x, 0.25, h.z)))
            scene.rootNode.addChildNode(Accessories.node(SCNCylinder(radius: 0.48, height: 0.02), pit, at: SCNVector3(h.x, -0.48, h.z)))
            let plate = SCNTube(innerRadius: 0.5, outerRadius: 0.565, height: 0.04)
            plate.radialSegmentCount = 64
            scene.rootNode.addChildNode(Accessories.node(plate, plates[(i + i / 3) % 3], at: SCNVector3(h.x, 1.02, h.z)))
            let rim = SCNTorus(ringRadius: 0.5, pipeRadius: 0.065)
            rim.ringSegmentCount = 72
            scene.rootNode.addChildNode(Accessories.node(rim, rimM, at: SCNVector3(h.x, 1.05, h.z)))
            for k in 0..<6 {
                let a = Float(k) / 6 * 2 * .pi + 0.26
                scene.rootNode.addChildNode(Accessories.node(SCNSphere(radius: 0.018), bolt, at: SCNVector3(h.x + 0.535 * cos(a), 1.045, h.z + 0.535 * sin(a))))
            }
        }
        // White rail around the top of the cabinet.
        for (x, z, w, d) in [(0, 1.92, 4.72, 0.14), (0, -1.92, 4.72, 0.14), (-2.29, 0, 0.14, 3.7), (2.29, 0, 0.14, 3.7)] as [(Float, Float, CGFloat, CGFloat)] {
            scene.rootNode.addChildNode(Accessories.node(SCNBox(width: w, height: 0.12, length: d, chamferRadius: 0.05), rimM, at: SCNVector3(x, 1.02, z)))
        }
        // Marquee bulbs along the front that chase.
        for (k, x) in stride(from: -2.05, through: 2.05, by: 0.34).enumerated() {
            let m = Accessories.material(CandySet.butter, roughness: 0.2)
            m.emission.contents = CandySet.butter
            let bulb = Accessories.node(SCNSphere(radius: 0.07), m, at: SCNVector3(Float(x), 0.62, 2.0))
            scene.rootNode.addChildNode(bulb)
            let on = SCNAction.customAction(duration: 0.01) { n, _ in n.geometry?.firstMaterial?.emission.intensity = 1 }
            let off = SCNAction.customAction(duration: 0.01) { n, _ in n.geometry?.firstMaterial?.emission.intensity = 0.1 }
            bulb.runAction(.sequence([.wait(duration: Double(k % 3) * 0.2),
                                      .repeatForever(.sequence([on, .wait(duration: 0.2), off, .wait(duration: 0.4)]))]))
        }
        let wall = Accessories.material(CandySet.bubblegum, roughness: 0.65)
        for (x, z, w, d) in [(0, 1.95, 4.6, 0.1), (0, -1.95, 4.6, 0.1), (-2.3, 0, 0.1, 3.9), (2.3, 0, 0.1, 3.9)] as [(Float, Float, CGFloat, CGFloat)] {
            scene.rootNode.addChildNode(Accessories.node(SCNBox(width: w, height: 1.6, length: d, chamferRadius: 0), wall, at: SCNVector3(x, 0.1, z)))
        }
    }
}
