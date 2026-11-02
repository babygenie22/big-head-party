import SceneKit
import UIKit

/// The county-fair booth around the Whack-a-Head board: a striped prize booth with shelves of
/// plush bears, a glowing marquee sign, a scalloped awning, chasing bulbs, bunting and a bunch of
/// balloons, in a real park at sunset (`Location.fairground`).
///
/// The game camera looks down at the board and the score bar covers the top of the screen, so
/// only what stands just behind the board shows: everything here sits within a few units of it.
enum Fairground {
    static let red = UIColor(red: 0.82, green: 0.09, blue: 0.1, alpha: 1)
    static let cream = UIColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1)
    static let gold = UIColor(red: 1, green: 0.76, blue: 0.16, alpha: 1)
    static let bulbColors = [UIColor(red: 1, green: 0.82, blue: 0.45, alpha: 1), UIColor(red: 1, green: 0.35, blue: 0.3, alpha: 1),
                             UIColor(red: 0.4, green: 0.75, blue: 1, alpha: 1), UIColor(red: 0.55, green: 1, blue: 0.5, alpha: 1)]

    static func build(in scene: SCNScene) {
        let root = SCNNode()
        root.name = "fairground"
        scene.rootNode.addChildNode(root)
        backWall(root)
        prizes(root)
        sign(root)
        awning(root)
        boardwalk(root)
        balloons(root, at: SCNVector3(-2.35, 0.9, -2.4))
        // Bunting strung across the booth, in front of the prizes.
        root.addChildNode(bunting(from: SCNVector3(-3.6, 3.3, -2.5), to: SCNVector3(3.6, 3.3, -2.5), sag: 0.3, flags: 19))
        root.enumerateHierarchy { n, _ in n.castsShadow = true }
    }

    // MARK: - Booth

    /// Striped canvas back wall and side flaps.
    private static func backWall(_ root: SCNNode) {
        let canvas = Surface.canvas(.white)
        canvas.diffuse.contents = stripes(cream, red, count: 14)
        canvas.diffuse.wrapS = .repeat
        canvas.normal.intensity = 0.3
        canvas.isDoubleSided = true
        let wall = SCNPlane(width: 7.6, height: 4.8)
        root.addChildNode(Accessories.node(wall, canvas, at: SCNVector3(0, 2.4, -3.3)))
        for side: Float in [-1, 1] {
            let flap = Accessories.node(SCNPlane(width: 2.6, height: 4.8), canvas, at: SCNVector3(side * 3.75, 2.4, -2.05))
            flap.eulerAngles.y = side * .pi / 2.3
            root.addChildNode(flap)
            // Barber-pole corner posts.
            let pole = Accessories.material(.white, roughness: 0.3)
            pole.diffuse.contents = stripes(.white, red, count: 2, diagonal: true)
            pole.diffuse.wrapS = .repeat; pole.diffuse.wrapT = .repeat
            pole.diffuse.contentsTransform = SCNMatrix4MakeScale(1, 6, 1)
            pole.clearCoat.contents = 0.6
            root.addChildNode(Accessories.node(SCNCylinder(radius: 0.09, height: 5.2), pole, at: SCNVector3(side * 3.75, 2.6, -3.25)))
            root.addChildNode(Accessories.node(SCNSphere(radius: 0.16), Surface.paintedMetal(gold), at: SCNVector3(side * 3.75, 5.25, -3.25)))
        }
    }

    /// Two shelves of plush bears.
    private static func prizes(_ root: SCNNode) {
        let wood = Surface.wood(UIColor(red: 0.62, green: 0.4, blue: 0.22, alpha: 1), planks: 3)
        let colors = [UIColor(red: 0.98, green: 0.62, blue: 0.75, alpha: 1), UIColor(red: 0.55, green: 0.78, blue: 1, alpha: 1),
                      UIColor(red: 1, green: 0.86, blue: 0.4, alpha: 1), UIColor(red: 0.68, green: 0.9, blue: 0.6, alpha: 1),
                      UIColor(red: 0.78, green: 0.62, blue: 0.95, alpha: 1), UIColor(red: 0.72, green: 0.5, blue: 0.32, alpha: 1)]
        var rng = SeededRandom(seed: 11)
        for (k, y) in [Float(1.25), 2.25].enumerated() {
            root.addChildNode(Accessories.node(SCNBox(width: 7.2, height: 0.08, length: 0.55, chamferRadius: 0.02), wood, at: SCNVector3(0, y, -3.0)))
            let count = 9 - k
            for i in 0..<count {
                let x = -3.1 + 6.2 * (Float(i) + 0.5) / Float(count)
                let size = 0.85 + Float(rng.next()) * 0.35
                let bear = teddy(colors[(i + k * 2) % colors.count], size: size * 0.75)
                bear.position = SCNVector3(x, y + 0.04, -2.95)
                bear.eulerAngles.y = Float(rng.next() - 0.5) * 0.6
                root.addChildNode(bear)
            }
        }
    }

    /// A sitting plush bear, about `size` tall, its feet at the origin.
    static func teddy(_ color: UIColor, size: Float) -> SCNNode {
        let bear = SCNNode()
        let fur = Fabric.cloth(color, roughness: 1, repeats: 4)
        let light = Fabric.cloth(color.blended(with: .white, 0.45), roughness: 1, repeats: 4)
        let eye = Accessories.material(UIColor(white: 0.04, alpha: 1), roughness: 0.15)
        func ball(_ r: CGFloat, _ m: SCNMaterial, _ p: SCNVector3, _ s: SCNVector3 = SCNVector3(1, 1, 1)) {
            let n = Accessories.node(SCNSphere(radius: r), m, at: p)
            n.scale = s
            bear.addChildNode(n)
        }
        ball(0.26, fur, SCNVector3(0, 0.27, 0), SCNVector3(1, 1.05, 0.9))          // body
        ball(0.15, light, SCNVector3(0, 0.25, 0.17), SCNVector3(1, 1.1, 0.5))      // tummy
        ball(0.2, fur, SCNVector3(0, 0.66, 0.02))                                 // head
        ball(0.075, light, SCNVector3(0, 0.62, 0.19), SCNVector3(1.1, 0.85, 0.8))  // muzzle
        ball(0.025, eye, SCNVector3(0, 0.65, 0.255))                              // nose
        for s: Float in [-1, 1] {
            ball(0.075, fur, SCNVector3(s * 0.15, 0.83, 0), SCNVector3(1, 1, 0.6))   // ears
            ball(0.04, light, SCNVector3(s * 0.15, 0.83, 0.03), SCNVector3(1, 1, 0.5))
            ball(0.03, eye, SCNVector3(s * 0.07, 0.71, 0.18))                     // eyes
            ball(0.09, fur, SCNVector3(s * 0.25, 0.34, 0.08), SCNVector3(0.8, 1.3, 0.8))   // arms
            ball(0.11, fur, SCNVector3(s * 0.14, 0.08, 0.16), SCNVector3(0.9, 0.75, 1.3))  // legs
            ball(0.06, light, SCNVector3(s * 0.14, 0.08, 0.3), SCNVector3(1, 1, 0.4))     // paw pads
        }
        bear.scale = SCNVector3(size, size, size)
        return bear
    }

    /// The marquee: a red board with gold lettering, ringed by chasing bulbs.
    private static func sign(_ root: SCNNode) {
        let w: CGFloat = 3.2, h: CGFloat = 0.66
        let signY: Float = 3.5, signZ: Float = -0.55
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 208)).image { ctx in
            let r = CGRect(x: 0, y: 0, width: 1024, height: 208)
            UIColor(red: 0.55, green: 0.04, blue: 0.06, alpha: 1).setFill(); ctx.fill(r)
            let inner = r.insetBy(dx: 14, dy: 14)
            let border = UIBezierPath(roundedRect: inner, cornerRadius: 26)
            border.lineWidth = 10
            gold.setStroke(); border.stroke()
            let font = UIFont.systemFont(ofSize: 132, weight: .black).withCondensed()
            let shadow = NSShadow(); shadow.shadowColor = UIColor(white: 0, alpha: 0.5); shadow.shadowOffset = CGSize(width: 0, height: 6)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(red: 1, green: 0.88, blue: 0.3, alpha: 1),
                                                        .strokeColor: UIColor(red: 0.35, green: 0.02, blue: 0.03, alpha: 1), .strokeWidth: -4, .shadow: shadow]
            let text = NSAttributedString(string: "WHACK-A-HEAD", attributes: attrs)
            let size = text.size()
            text.draw(at: CGPoint(x: (1024 - size.width) / 2, y: (208 - size.height) / 2))
        }
        let m = Accessories.material(.white, roughness: 0.4)
        m.diffuse.contents = image
        m.emission.contents = image
        m.emission.intensity = 0.35
        let board = Accessories.node(SCNBox(width: w, height: h, length: 0.08, chamferRadius: 0.03), m, at: SCNVector3(0, signY, signZ))
        let back = Surface.paintedMetal(UIColor(red: 0.55, green: 0.04, blue: 0.06, alpha: 1))
        board.geometry?.materials = [m, back, back, back, back, back]
        root.addChildNode(board)
        // Bulbs all the way round, chasing.
        var points: [SCNVector3] = []
        let nx = 12, ny = 3
        for i in 0...nx { let x = Float(-w / 2) + Float(w) * Float(i) / Float(nx); points += [SCNVector3(x, signY + Float(h / 2) + 0.05, signZ + 0.06), SCNVector3(x, signY - Float(h / 2) - 0.05, signZ + 0.06)] }
        for j in 1..<ny { let y = signY - Float(h / 2) + Float(h) * Float(j) / Float(ny); points += [SCNVector3(Float(-w / 2) - 0.06, y, signZ + 0.06), SCNVector3(Float(w / 2) + 0.06, y, signZ + 0.06)] }
        // Chains up to the awning.
        let chain = Surface.steel
        for side: Float in [-1, 1] {
            root.addChildNode(Accessories.node(SCNCylinder(radius: 0.012, height: 0.5), chain, at: SCNVector3(side * Float(w) * 0.4, signY + Float(h / 2) + 0.25, signZ)))
        }
        for (k, p) in points.enumerated() {
            root.addChildNode(bulb(color: bulbColors[0], radius: 0.04, at: p, phase: k % 3))
        }
    }

    /// The scalloped, striped valance hanging across the top of the view, with a string of
    /// coloured bulbs along its edge.
    private static func awning(_ root: SCNNode) {
        let scallops = 11
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1100, height: 120)).image { ctx in
            let stripe = 1100.0 / CGFloat(scallops)
            for i in 0..<scallops {
                (i % 2 == 0 ? red : cream).setFill()
                let x = CGFloat(i) * stripe
                let path = UIBezierPath(rect: CGRect(x: x, y: 0, width: stripe, height: 70))
                path.append(UIBezierPath(ovalIn: CGRect(x: x, y: 20, width: stripe, height: 100)))
                path.fill()
            }
            gold.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1100, height: 10))
        }
        let m = Accessories.material(.white, roughness: 0.85)
        m.diffuse.contents = image
        m.transparent.contents = image
        m.transparencyMode = .aOne
        m.isDoubleSided = true
        m.normal.contents = Fabric.knitNormal
        m.normal.intensity = 0.25
        let valance = Accessories.node(SCNPlane(width: 7.6, height: 0.8), m, at: SCNVector3(0, 4.35, -0.5))
        valance.eulerAngles.x = -0.15
        root.addChildNode(valance)
        for i in 0..<16 {
            let x = -3.4 + 6.8 * Float(i) / 15
            root.addChildNode(bulb(color: bulbColors[i % bulbColors.count], radius: 0.06, at: SCNVector3(x, 3.98, -0.45), phase: i % 2))
        }
    }

    /// A wooden boardwalk under the booth, littered with confetti, a popcorn bucket and a
    /// dropped cotton candy.
    private static func boardwalk(_ root: SCNNode) {
        let wood = Surface.wood(UIColor(red: 0.6, green: 0.42, blue: 0.26, alpha: 1), planks: 8)
        wood.diffuse.contentsTransform = SCNMatrix4MakeScale(1.5, 1.5, 1)
        wood.roughness.contents = 0.7
        wood.clearCoat.contents = 0.1
        let deck = Accessories.node(SCNBox(width: 9, height: 0.06, length: 9.5, chamferRadius: 0.01), wood, at: SCNVector3(0, 0.03, 1.2))
        root.addChildNode(deck)
        var rng = SeededRandom(seed: 21)
        let colors = [red, gold, UIColor(red: 0.2, green: 0.55, blue: 1, alpha: 1), UIColor(red: 0.95, green: 0.45, blue: 0.75, alpha: 1),
                      UIColor(red: 0.3, green: 0.8, blue: 0.45, alpha: 1), cream]
        let paper = colors.map { c -> SCNMaterial in let m = Accessories.material(c, roughness: 0.6); m.isDoubleSided = true; return m }
        for _ in 0..<90 {
            let piece = Accessories.node(SCNPlane(width: 0.06, height: 0.035), paper.randomElement()!,
                                         at: SCNVector3(Float(rng.next() - 0.5) * 6.4, 0.065, 2.15 + Float(rng.next()) * 3.2))
            piece.eulerAngles = SCNVector3(-.pi / 2, Float(rng.next()) * 6.28, 0)
            piece.castsShadow = false
            root.addChildNode(piece)
        }
        // Popcorn in a striped bucket.
        let bucketM = Accessories.material(.white, roughness: 0.6)
        bucketM.diffuse.contents = stripes(.white, red, count: 8)
        bucketM.diffuse.wrapS = .repeat
        let bucket = SCNNode()
        bucket.position = SCNVector3(-1.55, 0.06, 2.75)
        bucket.addChildNode(Accessories.node(SCNCone(topRadius: 0.27, bottomRadius: 0.2, height: 0.5), bucketM, at: SCNVector3(0, 0.25, 0)))
        let kernel = Accessories.material(UIColor(red: 1, green: 0.95, blue: 0.78, alpha: 1), roughness: 0.85)
        let butter = Accessories.material(UIColor(red: 1, green: 0.84, blue: 0.45, alpha: 1), roughness: 0.7)
        for k in 0..<34 {
            let a = Float(rng.next()) * 6.28, r = sqrt(Float(rng.next())) * 0.24
            let kp = Accessories.node(SCNSphere(radius: 0.045 + CGFloat(rng.next()) * 0.02), k % 4 == 0 ? butter : kernel,
                                      at: SCNVector3(cos(a) * r, 0.5 + (0.24 - r) * 0.5 + Float(rng.next()) * 0.06, sin(a) * r))
            kp.scale = SCNVector3(1, 0.8 + Float(rng.next()) * 0.3, 1)
            bucket.addChildNode(kp)
        }
        for _ in 0..<6 {   // a few spilled
            bucket.addChildNode(Accessories.node(SCNSphere(radius: 0.045), kernel,
                                                 at: SCNVector3(Float(rng.next() - 0.3) * 0.9, 0.04, Float(rng.next() - 0.2) * 0.6)))
        }
        root.addChildNode(bucket)
        // Cotton candy on a paper cone, dropped on its side.
        let candy = SCNNode()
        candy.position = SCNVector3(1.6, 0.2, 2.9)
        candy.eulerAngles = SCNVector3(0, -0.6, .pi / 2.2)
        let cone = Accessories.material(UIColor(red: 0.98, green: 0.95, blue: 0.9, alpha: 1), roughness: 0.7)
        candy.addChildNode(Accessories.node(SCNCone(topRadius: 0.05, bottomRadius: 0.012, height: 0.36), cone, at: SCNVector3(0, -0.2, 0)))
        let fluff = Fabric.cloth(UIColor(red: 1, green: 0.62, blue: 0.82, alpha: 1), roughness: 1, repeats: 2)
        fluff.emission.contents = UIColor(red: 0.2, green: 0.06, blue: 0.12, alpha: 1)   // a little translucent glow
        for k in 0..<7 {
            let a = Float(k) / 7 * 6.28
            let puff = Accessories.node(SCNSphere(radius: 0.13), fluff, at: SCNVector3(cos(a) * 0.09, 0.12 + Float(k % 3) * 0.05, sin(a) * 0.09))
            candy.addChildNode(puff)
        }
        candy.addChildNode(Accessories.node(SCNSphere(radius: 0.15), fluff, at: SCNVector3(0, 0.2, 0)))
        root.addChildNode(candy)
    }

    /// A glowing bulb that blinks in one of three phases, so rows of them chase.
    private static func bulb(color: UIColor, radius: CGFloat, at p: SCNVector3, phase: Int) -> SCNNode {
        let m = Accessories.material(color.blended(with: .white, 0.5), roughness: 0.1)
        m.emission.contents = color
        let n = Accessories.node(SCNSphere(radius: radius), m, at: p)
        n.castsShadow = false
        let on = SCNAction.customAction(duration: 0.01) { node, _ in node.geometry?.firstMaterial?.emission.intensity = 2.2 }
        let off = SCNAction.customAction(duration: 0.01) { node, _ in node.geometry?.firstMaterial?.emission.intensity = 0.35 }
        n.runAction(.sequence([.wait(duration: Double(phase) * 0.22),
                               .repeatForever(.sequence([on, .wait(duration: 0.22), off, .wait(duration: 0.44)]))]))
        return n
    }

    /// Triangle flags along a sagging cord.
    private static func bunting(from a: SCNVector3, to b: SCNVector3, sag: Float, flags: Int) -> SCNNode {
        let node = SCNNode()
        let colors = [red, gold, UIColor(red: 0.15, green: 0.45, blue: 0.9, alpha: 1), cream, UIColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1)]
        func point(_ t: Float) -> SCNVector3 {
            SCNVector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t - sag * 4 * t * (1 - t), a.z + (b.z - a.z) * t)
        }
        let triangle = UIBezierPath()
        triangle.move(to: CGPoint(x: -0.14, y: 0)); triangle.addLine(to: CGPoint(x: 0.14, y: 0)); triangle.addLine(to: CGPoint(x: 0, y: -0.32)); triangle.close()
        for i in 0..<flags {
            let t = (Float(i) + 0.5) / Float(flags)
            let shape = SCNShape(path: triangle, extrusionDepth: 0.005)
            let m = Fabric.cloth(colors[i % colors.count], roughness: 0.9, repeats: 2)
            m.isDoubleSided = true
            let flag = Accessories.node(shape, m, at: point(t))
            flag.runAction(.repeatForever(.sequence([.rotateTo(x: 0.25, y: 0, z: 0, duration: 0.9 + Double(i % 3) * 0.15),
                                                     .rotateTo(x: -0.1, y: 0, z: 0, duration: 0.9 + Double(i % 3) * 0.15)])))
            node.addChildNode(flag)
        }
        let cord = Accessories.material(UIColor(white: 0.95, alpha: 1), roughness: 0.8)
        for i in 0..<24 {
            let p0 = point(Float(i) / 24), p1 = point(Float(i + 1) / 24)
            let seg = SCNNode(geometry: SCNCylinder(radius: 0.008, height: CGFloat(simd_distance(SIMD3<Float>(p0), SIMD3<Float>(p1)))))
            seg.geometry?.materials = [cord]
            seg.simdPosition = (SIMD3<Float>(p0) + SIMD3<Float>(p1)) / 2
            seg.simdLook(at: SIMD3<Float>(p1), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 1, 0))
            node.addChildNode(seg)
        }
        return node
    }

    /// A bunch of glossy balloons on strings, bobbing in the breeze.
    private static func balloons(_ root: SCNNode, at anchor: SCNVector3) {
        let colors = [red, gold, UIColor(red: 0.2, green: 0.55, blue: 1, alpha: 1), UIColor(red: 0.95, green: 0.45, blue: 0.75, alpha: 1), UIColor(red: 0.3, green: 0.8, blue: 0.45, alpha: 1)]
        let string = Accessories.material(.white, roughness: 0.8)
        var rng = SeededRandom(seed: 4)
        for (i, color) in colors.enumerated() {
            let holder = SCNNode()
            holder.position = anchor
            let length = 1.9 + Float(rng.next()) * 0.7
            let lean = SCNVector3(Float(rng.next() - 0.5) * 0.5, 0, Float(rng.next() - 0.5) * 0.3)
            holder.eulerAngles = SCNVector3(lean.z, 0, lean.x)
            let m = Surface.plastic(color)
            m.clearCoat.contents = 1
            m.roughness.contents = 0.15
            let balloon = Accessories.node(SCNSphere(radius: 0.26), m, at: SCNVector3(0, length, 0))
            balloon.scale = SCNVector3(1, 1.2, 1)
            holder.addChildNode(balloon)
            holder.addChildNode(Accessories.node(SCNCone(topRadius: 0, bottomRadius: 0.04, height: 0.06), m, at: SCNVector3(0, length - 0.33, 0)))
            holder.addChildNode(Accessories.node(SCNCylinder(radius: 0.005, height: CGFloat(length - 0.3)), string, at: SCNVector3(0, (length - 0.3) / 2, 0)))
            let sway = Double(1.6 + rng.next() * 0.8)
            holder.runAction(.sequence([.wait(duration: Double(i) * 0.3), .repeatForever(.sequence([
                .rotateBy(x: 0.06, y: 0, z: 0.09, duration: sway), .rotateBy(x: -0.06, y: 0, z: -0.09, duration: sway)]))]))
            root.addChildNode(holder)
        }
    }

    // MARK: - Textures

    /// Vertical (or diagonal, for barber poles) stripes, tiling horizontally.
    private static func stripes(_ a: UIColor, _ b: UIColor, count: Int, diagonal: Bool = false) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512)).image { ctx in
            a.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            b.setFill()
            let w = 512 / CGFloat(count * 2)
            for i in 0..<count {
                let x = CGFloat(i * 2) * w
                if diagonal {
                    let p = UIBezierPath()
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + w, y: 0))
                    p.addLine(to: CGPoint(x: x + w + 512, y: 512)); p.addLine(to: CGPoint(x: x + 512, y: 512)); p.close()
                    p.fill()
                    p.apply(CGAffineTransform(translationX: -512, y: 0)); p.fill()
                } else {
                    ctx.fill(CGRect(x: x, y: 0, width: w, height: 512))
                }
            }
        }
    }
}

private extension UIColor {
    func blended(with other: UIColor, _ t: CGFloat) -> UIColor {
        let a = rgba, b = other.rgba
        return UIColor(red: a.r + (b.r - a.r) * t, green: a.g + (b.g - a.g) * t, blue: a.b + (b.b - a.b) * t, alpha: 1)
    }
}

private extension UIFont {
    func withCondensed() -> UIFont {
        guard let d = fontDescriptor.withSymbolicTraits(.traitCondensed) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}
