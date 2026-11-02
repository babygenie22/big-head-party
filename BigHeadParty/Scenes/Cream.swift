import SceneKit
import UIKit

/// Realistic pie mess: whipped cream that builds up on the face (`CreamCoat`), lumpy dollops
/// with soft peaks and crust crumbs. Geometry is built once and reused.
enum Cream {
    // MARK: - Materials

    /// Whipped cream: warm off-white, soft lumpy surface, a faint wet sheen, and a little
    /// self-glow so shadowed folds stay creamy instead of going grey (cheap subsurface).
    static let material: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 1.0, green: 0.975, blue: 0.92, alpha: 1)
        m.roughness.contents = 0.42
        m.metalness.contents = 0
        m.clearCoat.contents = 0.35
        m.clearCoatRoughness.contents = 0.3
        m.emission.contents = UIColor(red: 0.16, green: 0.14, blue: 0.11, alpha: 1)
        m.normal.contents = lumpNormal
        m.normal.intensity = 0.6
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
        m.isDoubleSided = true
        return m
    }()

    /// Baked pie crust: golden brown, rough, slightly darker at random.
    static let crustMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 0.80, green: 0.56, blue: 0.29, alpha: 1)
        m.roughness.contents = 0.85
        m.normal.contents = lumpNormal
        m.normal.intensity = 1
        m.isDoubleSided = true
        return m
    }()

    /// Soft, cloudy normal map for whipped cream (fine bubbles over gentle lumps).
    static let lumpNormal: UIImage = {
        let n = 256
        var height = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let u = Float(x) / Float(n), v = Float(y) / Float(n)
                height[y * n + x] = tiledNoise(u * 6, v * 6, period: 6) * 0.7 + tiledNoise(u * 24, v * 24, period: 24) * 0.3
            }
        }
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let dx = height[y * n + (x + 1) % n] - height[y * n + (x + n - 1) % n]
                let dy = height[((y + 1) % n) * n + x] - height[((y + n - 1) % n) * n + x]
                var nx = -dx * 4, ny = -dy * 4, nz: Float = 1
                let l = sqrt(nx * nx + ny * ny + nz * nz); nx /= l; ny /= l; nz /= l
                let i = (y * n + x) * 4
                px[i] = UInt8((nx * 0.5 + 0.5) * 255); px[i + 1] = UInt8((ny * 0.5 + 0.5) * 255); px[i + 2] = UInt8((nz * 0.5 + 0.5) * 255)
            }
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: cg)
    }()

    // MARK: - Noise

    private static func hash(_ x: Int, _ y: Int, _ z: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ z &* 2147483647)
        h = (h ^ (h >> 13)) &* 1274126177
        return Float((h ^ (h >> 16)) & 0xFFFF) / Float(0xFFFF) - 0.5
    }

    private static func smooth(_ t: Float) -> Float { t * t * (3 - 2 * t) }

    /// Value noise in roughly −0.5…0.5.
    static func noise(_ x: Float, _ y: Float, _ z: Float = 0) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y)), zi = Int(floor(z))
        let fx = smooth(x - floor(x)), fy = smooth(y - floor(y)), fz = smooth(z - floor(z))
        func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
        let c00 = lerp(hash(xi, yi, zi), hash(xi + 1, yi, zi), fx), c10 = lerp(hash(xi, yi + 1, zi), hash(xi + 1, yi + 1, zi), fx)
        let c01 = lerp(hash(xi, yi, zi + 1), hash(xi + 1, yi, zi + 1), fx), c11 = lerp(hash(xi, yi + 1, zi + 1), hash(xi + 1, yi + 1, zi + 1), fx)
        return lerp(lerp(c00, c10, fy), lerp(c01, c11, fy), fz)
    }

    private static func tiledNoise(_ x: Float, _ y: Float, period: Int) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = smooth(x - floor(x)), fy = smooth(y - floor(y))
        func h(_ a: Int, _ b: Int) -> Float { hash(((a % period) + period) % period, ((b % period) + period) % period, 7) }
        let top = h(xi, yi) + (h(xi + 1, yi) - h(xi, yi)) * fx
        let bottom = h(xi, yi + 1) + (h(xi + 1, yi + 1) - h(xi, yi + 1)) * fx
        return top + (bottom - top) * fy
    }

    // MARK: - Dollops and crumbs

    /// Lumpy whipped dollops: a subdivided sphere pushed out by noise, with a pulled-up peak.
    static let dollops: [SCNGeometry] = (0..<5).map { k in lumpySphere(seed: Float(k) * 7.3, lump: 0.16, peak: 0.75, segments: 24, material: material) }

    /// Irregular crust chunks.
    static let crumbs: [SCNGeometry] = (0..<4).map { k in lumpySphere(seed: Float(k) * 3.1 + 40, lump: 0.6, peak: 0, segments: 8, material: crustMaterial) }

    private static func lumpySphere(seed: Float, lump: Float, peak: Float, segments: Int, material: SCNMaterial) -> SCNGeometry {
        let rings = segments, sectors = segments * 2
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = []
        var indices: [UInt16] = []
        func point(_ theta: Float, _ phi: Float) -> SIMD3<Float> {
            let dir = SIMD3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
            var r = 1 + noise(dir.x * 2.2 + seed, dir.y * 2.2, dir.z * 2.2) * lump + noise(dir.x * 6 + seed, dir.y * 6, dir.z * 6) * lump * 0.35
            // A soft peak at the top, like a piped swirl that slumped.
            r += peak * pow(max(0, dir.y), 6)
            return dir * r
        }
        for i in 0...rings {
            let theta = Float(i) / Float(rings) * .pi
            for j in 0...sectors {
                let phi = Float(j) / Float(sectors) * 2 * .pi
                let p = point(theta, phi)
                // Normal by finite differences on the displaced surface.
                let e: Float = 0.01
                let pt = point(theta + e, phi), pp = point(theta, phi + e)
                var nrm = simd_cross(pp - p, pt - p)
                if simd_dot(nrm, p) < 0 { nrm = -nrm }
                nrm = simd_length(nrm) > 0 ? simd_normalize(nrm) : simd_normalize(p)
                positions.append(SCNVector3(p.x, p.y, p.z))
                normals.append(SCNVector3(nrm.x, nrm.y, nrm.z))
                uvs.append(CGPoint(x: CGFloat(j) / CGFloat(sectors), y: CGFloat(i) / CGFloat(rings)))
            }
        }
        for i in 0..<rings {
            for j in 0..<sectors {
                let a = UInt16(i * (sectors + 1) + j), b = a + 1, c = a + UInt16(sectors + 1), d = c + 1
                indices += [a, b, c, b, d, c]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals),
                                      SCNGeometrySource(textureCoordinates: uvs)],
                            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        g.materials = [material]
        return g
    }

    /// Soft cream flecks for the splash burst (a fuzzy blob, not a hard dot).
    static let fleckImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
        let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.85).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
        ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }
}

/// The cream on one head: a shell the shape of the head that sits just under the skin until
/// pies land. Every splat adds cream where it hits, so the face fills up and the layer gets
/// thicker throw after throw. It follows the face's expressions through its own morpher.
final class CreamCoat {
    let node = SCNNode()
    private let base: [SIMD3<Float>]
    private let baseNormals: [SIMD3<Float>]
    private let lumps: [Float]
    private let cols: Int, rows: Int
    private let element: SCNGeometryElement
    private let uvs: SCNGeometrySource
    private var amount: [Float]
    private(set) var positions: [SIMD3<Float>]
    private(set) var normals: [SIMD3<Float>]
    private(set) var splats = 0

    /// Cream is visible where the amount passes this.
    private static let threshold: Float = 0.3

    static let material: SCNMaterial = {
        let m = Cream.material.copy() as! SCNMaterial
        m.normal.contentsTransform = SCNMatrix4MakeScale(7, 7, 1)
        m.isDoubleSided = false
        return m
    }()

    init?(head: SCNGeometry, targets: [SCNGeometry], cols: Int) {
        guard let v = head.sources(for: .vertex).first, let n = head.sources(for: .normal).first,
              let uv = head.sources(for: .texcoord).first, let e = head.elements.first else { return nil }
        base = Self.read(v); baseNormals = Self.read(n)
        guard base.count == baseNormals.count, base.count % cols == 0 else { return nil }
        self.cols = cols; rows = base.count / cols
        element = e; uvs = uv
        amount = [Float](repeating: 0, count: base.count)
        lumps = base.map { p in Cream.noise(p.x * 6, p.y * 6, p.z * 6) + Cream.noise(p.x * 15 + 9, p.y * 15, p.z * 15) * 0.45 }
        positions = base; normals = baseNormals

        // Expressions as deltas, so they still apply however thick the cream gets.
        let morpher = SCNMorpher()
        morpher.calculationMode = .additive
        let base = base, baseNormals = baseNormals
        morpher.targets = targets.compactMap { t in
            guard let tv = t.sources(for: .vertex).first, let tn = t.sources(for: .normal).first else { return nil }
            let tp = Self.read(tv), tnn = Self.read(tn)
            guard tp.count == base.count else { return nil }
            let dp = zip(tp, base).map { SCNVector3($0.x - $1.x, $0.y - $1.y, $0.z - $1.z) }
            let dn = zip(tnn, baseNormals).map { SCNVector3($0.x - $1.x, $0.y - $1.y, $0.z - $1.z) }
            let g = SCNGeometry(sources: [SCNGeometrySource(vertices: dp), SCNGeometrySource(normals: dn)], elements: [e])
            g.name = t.name
            return g
        }
        node.name = "creamCoat"
        node.morpher = morpher
        rebuild()
    }

    private static func read(_ s: SCNGeometrySource) -> [SIMD3<Float>] {
        s.data.withUnsafeBytes { raw in
            (0..<s.vectorCount).map { i in
                let o = s.dataOffset + i * s.dataStride
                return SIMD3(raw.load(fromByteOffset: o, as: Float.self),
                             raw.load(fromByteOffset: o + 4, as: Float.self),
                             raw.load(fromByteOffset: o + 8, as: Float.self))
            }
        }
    }

    /// Adds a splat of cream centered at head-model (x, y), with a few runs dripping down from
    /// its lower edge. Returns spots on the new cream (with outward normals) where dollops and
    /// crumbs can sit.
    @discardableResult
    func splat(center: SIMD2<Float>, radius: Float, seed: Float) -> [(SIMD3<Float>, SIMD3<Float>)] {
        splats += 1
        let runs: [(x: Float, top: Float, length: Float, width: Float)] = (0..<Int.random(in: 2...4)).map { _ in
            (center.x + Float.random(in: -0.6...0.6) * radius, center.y - radius * Float.random(in: 0.45...0.6),
             Float.random(in: 0.3...0.75), Float.random(in: 0.09...0.13))
        }
        var inside: [Int] = []
        for k in base.indices {
            let nrm = baseNormals[k]
            guard nrm.z > -0.25 else { continue }   // the face, cheeks, forehead and sides — not the back
            let p = base[k]
            let dx = p.x - center.x, dy = p.y - center.y
            let d = sqrt(dx * dx + dy * dy)
            let angle = atan2(dy, dx)
            let reach = radius * (0.85 + Cream.noise(cos(angle) * 1.7 + seed, sin(angle) * 1.7 + seed) * 0.5)
            var add: Float = 0
            if d < reach {
                // Fades a touch toward the sides, where the pie hits at a glancing angle.
                add = 1.6 * min(1, 1.6 * (1 - d / reach)) * (0.6 + 0.4 * max(0, nrm.z))
                if d < reach * 0.55 && nrm.z > 0.35 { inside.append(k) }
            }
            // Runs: rounded streaks down the face (capsules), a little fatter at the bottom where
            // the drop gathers.
            for r in runs where p.y < r.top + 0.1 && p.y > r.top - r.length - 0.25 {
                let along = max(0, min(1, (r.top - p.y) / r.length))
                let w = r.width * (0.85 + 0.4 * along * along)
                let ex = p.x - r.x, ey = p.y - (r.top - along * r.length)
                let dist = sqrt(ex * ex + ey * ey)
                guard dist < w else { continue }
                add = max(add, 1.0 * min(1, 2 * (1 - dist / w)))
            }
            if add > 0 { amount[k] = min(3, amount[k] + add) }
        }
        rebuild()
        return inside.map { (positions[$0], normals[$0]) }
    }

    /// Wipes the face clean (the shell drops back under the skin).
    func reset() {
        amount = [Float](repeating: 0, count: base.count)
        splats = 0
        rebuild()
    }

    private func rebuild() {
        for k in base.indices {
            let a = amount[k] - Self.threshold
            // Continuous through the edge (signed), so the outline is the smooth curve where the
            // sheet comes up out of the skin, not the mesh grid.
            var t = max(-0.03, min(0.16, a * 0.22))
            if a > 0 { t += lumps[k] * 0.035 * min(1, a * 3) }
            positions[k] = base[k] + baseNormals[k] * t
        }
        // Normals from the shell itself, so lumps and edges catch the light.
        for r in 0..<rows {
            for c in 0..<cols {
                let k = r * cols + c
                let l = positions[r * cols + max(c - 1, 0)], rt = positions[r * cols + min(c + 1, cols - 1)]
                let up = positions[max(r - 1, 0) * cols + c], dn = positions[min(r + 1, rows - 1) * cols + c]
                var nn = simd_cross(rt - l, dn - up)
                if simd_dot(nn, baseNormals[k]) < 0 { nn = -nn }
                normals[k] = simd_length(nn) > 1e-6 ? simd_normalize(nn) : baseNormals[k]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) }),
                                      SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) }), uvs],
                            elements: [element])
        g.materials = [Self.material]
        // The morpher binds to the geometry it was attached with, so re-attach it to the new one.
        let morpher = node.morpher
        node.morpher = nil
        node.geometry = g
        node.morpher = morpher
    }
}
