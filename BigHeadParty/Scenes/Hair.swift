import SceneKit
import UIKit
import simd

/// Real 3D hair: a shell grown out of the scalp, thick over the crown and thinning to nothing at
/// a ragged hairline, combed into clumps that run down from the crown. It is built on the head's
/// own vertex grid, so it sits exactly on this person's skull and follows every expression
/// (same trick as `CreamCoat`). Long hair leaves the skull below the ears and hangs as a curtain.
///
/// The photo keeps its own fringe on the forehead; the shell starts at the top of the forehead
/// and gives the crown, sides and back the volume and silhouette paint can't.
enum Hair {
    /// Strand texture: light streaks running down the v axis, tinted by the hair colour.
    static let strands: UIImage = strandImage(normal: false)
    static let strandNormal: UIImage = strandImage(normal: true)

    static let roughness: CGFloat = 0.55

    static func material(_ color: UIColor) -> SCNMaterial {
        let m = Accessories.material(.white, roughness: roughness)
        m.diffuse.contents = strands
        m.multiply.contents = color
        m.normal.contents = strandNormal
        m.normal.intensity = 0.55
        for p in [m.diffuse, m.normal] {
            p.wrapS = .repeat
            p.wrapT = .repeat
        }
        m.isDoubleSided = true   // the underside of long hair shows beside the jaw
        return m
    }

    /// True when the texture has painted hair on the crown (false for bald heads, whose crown is
    /// filled with skin).
    static func hasHair(_ character: GameCharacter) -> Bool {
        // The crown fill sits near the top-left corner of the texture.
        guard let crown = average(of: character.texture, u: 0.05, v: 0.04, w: 0.08, h: 0.06) else { return false }
        let skin = character.meta.skinRGB, c = crown.rgba
        guard skin.count == 3 else { return true }
        let d = abs(Float(c.r) - skin[0] * 0.95) + abs(Float(c.g) - skin[1] * 0.95) + abs(Float(c.b) - skin[2] * 0.95)
        return d > 0.2
    }

    /// Hair colour for the shell: the stored colour pulled halfway toward the photo's own hair
    /// just above the forehead, so the shell and the photo's fringe match.
    static func color(for character: GameCharacter) -> UIColor {
        let stored = UIColor(rgb: character.meta.hairRGB)
        guard hasHair(character), let photo = average(of: character.texture, u: 0.42, v: 0.12, w: 0.16, h: 0.06) else { return stored }
        let a = stored.rgba, b = photo.rgba
        return UIColor(red: (a.r + b.r) / 2, green: (a.g + b.g) / 2, blue: (a.b + b.b) / 2, alpha: 1)
    }

    /// Average colour of a patch of a texture (u, v from the top-left corner).
    private static func average(of image: UIImage, u: CGFloat, v: CGFloat, w: CGFloat, h: CGFloat) -> UIColor? {
        guard let cg = image.cgImage else { return nil }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        var px = [UInt8](repeating: 0, count: 4)
        guard let patch = cg.cropping(to: CGRect(x: u * W, y: v * H, width: w * W, height: h * H)),
              let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
    }

    /// The hair shell for a head, or nil for styles that don't have one.
    /// `targets` are the head's blend shapes; the shell gets matching ones (as deltas).
    static func shell(head: SCNGeometry, targets: [SCNGeometry], cols: Int, eyeY: Float, chinY: Float,
                      long: Bool, color: UIColor) -> SCNNode? {
        // Sculpted once per head and style; every copy of that head (a game can hold several)
        // shares the mesh and wears its own material, so one can get wet or glow on its own.
        let key = Key(head: ObjectIdentifier(head), long: long)
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        guard let mesh = cached ?? sculpt(head: head, targets: targets, cols: cols, eyeY: eyeY, chinY: chinY, long: long) else { return nil }
        if cached == nil {
            lock.lock(); cache[key] = mesh; lock.unlock()
        }
        let geometry = mesh.geometry.copy() as! SCNGeometry
        geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry)
        node.name = "hairShell"
        let morpher = SCNMorpher()
        morpher.calculationMode = .additive
        morpher.targets = mesh.targets
        node.morpher = morpher
        return node
    }

    private struct Key: Hashable { let head: ObjectIdentifier; let long: Bool }
    private static var cache: [Key: (geometry: SCNGeometry, targets: [SCNGeometry])] = [:]
    private static let lock = NSLock()

    private static func sculpt(head: SCNGeometry, targets: [SCNGeometry], cols: Int, eyeY: Float, chinY: Float,
                               long: Bool) -> (geometry: SCNGeometry, targets: [SCNGeometry])? {
        guard let v = head.sources(for: .vertex).first, let n = head.sources(for: .normal).first else { return nil }
        let base = v.vectors, baseNormals = n.vectors
        guard base.count == baseNormals.count, base.count % cols == 0 else { return nil }
        let rows = base.count / cols, segments = cols - 1
        // The row at eye height: where long hair leaves the skull.
        let eyeRow = (0..<rows).min { abs(base[$0 * cols].y - eyeY) < abs(base[$1 * cols].y - eyeY) } ?? 0

        var positions = base
        var cover = [Float](repeating: 0, count: base.count)   // 0 at the hairline → 1 well inside
        var loose = [Bool](repeating: false, count: base.count) // hanging free of the skull
        var uvs = [CGPoint](repeating: .zero, count: base.count)
        for r in 0..<rows {
            for c in 0..<cols {
                let k = r * cols + c
                let a = -Float.pi + 2 * Float.pi * Float(c) / Float(segments)
                let ca = cos(a), p = base[k]
                // Hairline height: top of the forehead in front, over the ears at the sides, the
                // nape at the back; ragged, so its edge reads as strands rather than a cap.
                var line = ca >= 0 ? lerp(0.12, 0.95, t: smoothStep(0, 0.75, ca)) : lerp(0.12, -0.5, t: smoothStep(0, 0.6, -ca))
                line += 0.07 * (Cream.noise(a * 5, 3) - 0.5) + 0.04 * (Cream.noise(a * 17, 11) - 0.5)
                let hang = long ? smoothStep(0.3, 0.1, ca) : 0   // long hair: sides and back hang down
                if hang > 0 { line = lerp(line, -10, t: hang) }
                // In front the photo's own hair runs up under the shell, so it rises gently there.
                let inside = smoothStep(0, 0.2 + 0.2 * max(0, ca), p.y - (eyeY + line))
                cover[k] = inside
                // Clumps: ridges that run down from the crown, so thickness varies around the head.
                let clump = 0.72 + 0.4 * Cream.noise(a * 9, Float(r) * 0.05) + 0.2 * Cream.noise(a * 26, Float(r) * 0.12 + 5)
                let top = smoothStep(eyeY + 0.3, eyeY + 1.0, p.y)
                let thickness = (0.085 + 0.06 * top) * clump * inside - 0.03 * (1 - inside)
                var q = p + baseNormals[k] * thickness
                if hang > 0, r > eyeRow {
                    // Below the ears the skull curves in to the jaw; hair falls straight instead,
                    // flaring a little, and reaches past the chin.
                    let ref = base[eyeRow * cols + c], out = baseNormals[eyeRow * cols + c]
                    let fall = (eyeY - p.y) / max(eyeY - chinY, 0.1)
                    let flare = 1.03 + 0.1 * fall + 0.04 * sin(a * 7 + fall * 3)
                    let curtain = SIMD3(ref.x * flare, eyeY - (eyeY - p.y) * 1.3, -0.05 + (ref.z + 0.05) * flare)
                        + SIMD3(out.x, 0, out.z) * (0.11 * clump)
                    q = q + (curtain - q) * hang
                    loose[k] = hang > 0.5
                }
                positions[k] = q
                uvs[k] = CGPoint(x: CGFloat(c) / CGFloat(segments) * 5, y: CGFloat(r) / CGFloat(rows) * 1.6)
            }
        }

        // Only the hairy part: the rest of the grid stays under the skin and is never drawn.
        var indices: [UInt32] = []
        for r in 0..<(rows - 1) {
            for c in 0..<segments {
                let a = r * cols + c, b = a + cols
                guard cover[a] > 0 || cover[a + 1] > 0 || cover[b] > 0 || cover[b + 1] > 0 else { continue }
                indices += [a, b, a + 1, a + 1, b, b + 1].map(UInt32.init)
            }
        }
        guard !indices.isEmpty else { return nil }

        // Normals from the shell itself, so the clumps catch the light.
        var normals = baseNormals
        for r in 0..<rows {
            for c in 0..<cols {
                let k = r * cols + c
                let l = positions[r * cols + max(c - 1, 0)], rt = positions[r * cols + min(c + 1, cols - 1)]
                let up = positions[max(r - 1, 0) * cols + c], dn = positions[min(r + 1, rows - 1) * cols + c]
                var nn = simd_cross(rt - l, dn - up)
                if simd_dot(nn, baseNormals[k]) < 0 { nn = -nn }
                if simd_length(nn) > 1e-6 { normals[k] = simd_normalize(nn) }
            }
        }

        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) }),
                                             SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) }),
                                             SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: [element])
        // Expressions as deltas from the head's own blend shapes; hair hanging free doesn't move.
        let deltas: [SCNGeometry] = targets.compactMap { t in
            guard let tp = t.sources(for: .vertex).first?.vectors, tp.count == base.count else { return nil }
            let dp = base.indices.map { k -> SCNVector3 in
                let d = loose[k] ? .zero : tp[k] - base[k]
                return SCNVector3(d.x, d.y, d.z)
            }
            let g = SCNGeometry(sources: [SCNGeometrySource(vertices: dp),
                                          SCNGeometrySource(normals: [SCNVector3](repeating: SCNVector3Zero, count: dp.count))],
                                elements: [element])
            g.name = t.name
            return g
        }
        return (geometry, deltas)
    }

    /// A coiled bun: wraps of hair around a core, instead of a plain ball.
    static func bun(color: UIColor) -> SCNNode {
        let m = material(color)
        let bun = SCNNode()
        let core = Accessories.node(SCNSphere(radius: 0.3), m, at: SCNVector3Zero)
        core.scale = SCNVector3(1, 0.8, 1)
        bun.addChildNode(core)
        for (k, tilt) in [Float(0), 0.5, -0.45, 0.95].enumerated() {
            let wrap = Accessories.node(SCNTorus(ringRadius: 0.25 - CGFloat(k) * 0.02, pipeRadius: 0.11), m,
                                        at: SCNVector3(0, Float(k) * 0.035 - 0.04, 0))
            wrap.eulerAngles = SCNVector3(tilt * 0.5, Float(k) * 1.1, tilt * 0.35)
            bun.addChildNode(wrap)
        }
        return bun
    }

    private static func strandImage(normal: Bool) -> UIImage {
        let w = 256, h = 256
        // Height of the hair surface across the strands: fine strands on broader locks, which
        // wander a little on their way down so it doesn't read as ribbing. Tiles both ways.
        var rng = SeededRandom(seed: 23)
        let phases = (0..<8).map { _ in Float(rng.next()) * 2 * .pi }
        func height(_ x: Int, _ y: Int) -> Float {
            let t = Float(x) / Float(w) * 2 * .pi, s = Float(y) / Float(h) * 2 * .pi
            let drift = 0.5 * sin(s + phases[4]) + 0.3 * sin(2 * s + phases[5])
            return 0.5 + 0.17 * sin(t * 7 + phases[0] + drift * 1.4) + 0.13 * sin(t * 19 + phases[1] - drift * 2.2 + 0.6 * sin(3 * s + phases[6]))
                + 0.1 * sin(t * 43 + phases[2] + drift * 3) + 0.07 * sin(t * 89 + phases[3] + 1.5 * sin(2 * s + phases[7]))
        }
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let k = (y * w + x) * 4
                if normal {
                    let slope = simd_clamp((height(x + 1, y) - height(x - 1, y)) * 5, -1, 1)
                    px[k] = UInt8((0.5 - slope * 0.45) * 255); px[k + 1] = 128; px[k + 2] = 255
                } else {
                    // Mostly the hair colour, darker between locks, a touch lighter on their crests.
                    let v = UInt8(min(255, (0.7 + 0.34 * simd_clamp(height(x, y), 0, 1)) * 255))
                    px[k] = v; px[k + 1] = v; px[k + 2] = v
                }
            }
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: cg)
    }
}

extension SCNGeometrySource {
    /// The source's vectors as float triples (positions or normals).
    var vectors: [SIMD3<Float>] {
        data.withUnsafeBytes { raw in
            (0..<vectorCount).map { i in
                let o = dataOffset + i * dataStride
                return SIMD3(raw.load(fromByteOffset: o, as: Float.self),
                             raw.load(fromByteOffset: o + 4, as: Float.self),
                             raw.load(fromByteOffset: o + 8, as: Float.self))
            }
        }
    }
}
