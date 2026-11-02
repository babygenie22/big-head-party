import SceneKit
import UIKit

/// Realistic pie mess: a whipped-cream layer molded to the face's real surface, lumpy dollops
/// with soft peaks, crust crumbs and slow drips. Geometry is built once and reused.
extension SCNNode {
    /// The frontmost point of this node's own mesh at head-model (x, y), with an outward normal.
    /// Both sides are tested and the hit nearest the viewer wins, so the result never lands on
    /// the inside of the back of the head.
    func frontSurface(x: Float, y: Float) -> (point: SCNVector3, normal: SCNVector3)? {
        let hits = hitTestWithSegment(from: SCNVector3(x, y, 3), to: SCNVector3(x, y, -0.5),
                                      options: [SCNHitTestOption.backFaceCulling.rawValue: false])
        guard let hit = hits.filter({ $0.node === self }).max(by: { $0.localCoordinates.z < $1.localCoordinates.z }) else { return nil }
        var n = hit.localNormal
        if n.z < 0 { n = SCNVector3(-n.x, -n.y, -n.z) }
        return (hit.localCoordinates, n)
    }
}

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

    /// Smooth, glossier cream for drips (the lump map smears along their length).
    static let dripMaterial: SCNMaterial = {
        let m = material.copy() as! SCNMaterial
        m.normal.contents = nil
        m.roughness.contents = 0.3
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

    // MARK: - Molded layer

    /// A sheet of cream that follows the head mesh: a grid of rays around `center` (head-model
    /// x/y) lands on the face, and each vertex sits a little off the surface. Thickness peaks in
    /// the middle and the edge wanders with noise, so no two splats look alike.
    static func layer(on head: SCNNode, center: SIMD2<Float>, radius: Float, seed: Float) -> SCNNode? {
        let n = 40
        var positions = [SCNVector3](repeating: SCNVector3Zero, count: n * n)
        var normals = [SCNVector3](repeating: SCNVector3Zero, count: n * n)
        var uvs = [CGPoint](repeating: .zero, count: n * n)
        var valid = [Bool](repeating: false, count: n * n)
        for j in 0..<n {
            for i in 0..<n {
                let u = Float(i) / Float(n - 1) * 2 - 1, v = Float(j) / Float(n - 1) * 2 - 1
                let x = center.x + u * radius, y = center.y + v * radius
                // Organic outline: radius wobbles with angle.
                let angle = atan2(v, u)
                let edge = 0.78 + noise(cos(angle) * 1.6 + seed, sin(angle) * 1.6 + seed) * 0.5
                let r = sqrt(u * u + v * v)
                guard r < 1.05 else { continue }
                guard let hit = head.frontSurface(x: x, y: y) else { continue }
                // Past the wobbly edge the sheet dips just under the skin, so the visible outline
                // is the smooth curve where cream meets face, not the grid.
                let fall = 1 - smooth(min(1, r / edge))
                // Continuous through the edge (signed distance), so the crossing interpolates
                // smoothly between grid points instead of stepping.
                let rim = max(-0.03, min(0.02, (edge - r) * 0.12))
                let thickness = rim + 0.08 * fall * (0.75 + noise(x * 5 + seed, y * 5) * 0.8)
                let p = hit.point, nrm = hit.normal
                positions[j * n + i] = SCNVector3(p.x + nrm.x * thickness, p.y + nrm.y * thickness, p.z + nrm.z * thickness)
                normals[j * n + i] = nrm
                uvs[j * n + i] = CGPoint(x: CGFloat(u * 0.5 + 0.5), y: CGFloat(v * 0.5 + 0.5))
                valid[j * n + i] = true
            }
        }
        var indices: [UInt16] = []
        for j in 0..<(n - 1) {
            for i in 0..<(n - 1) {
                let a = j * n + i, b = a + 1, c = a + n, d = c + 1
                if valid[a] && valid[b] && valid[c] { indices += [UInt16(a), UInt16(b), UInt16(c)] }
                if valid[b] && valid[c] && valid[d] { indices += [UInt16(b), UInt16(d), UInt16(c)] }
            }
        }
        guard indices.count > 60 else { return nil }
        // Smooth normals from the sheet itself so the lumps catch light.
        var smoothN = [SIMD3<Float>](repeating: .zero, count: n * n)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let ia = Int(indices[t]), ib = Int(indices[t + 1]), ic = Int(indices[t + 2])
            let pa = SIMD3(positions[ia].x, positions[ia].y, positions[ia].z)
            let pb = SIMD3(positions[ib].x, positions[ib].y, positions[ib].z)
            let pc = SIMD3(positions[ic].x, positions[ic].y, positions[ic].z)
            let fn = simd_cross(pb - pa, pc - pa)
            smoothN[ia] += fn; smoothN[ib] += fn; smoothN[ic] += fn
        }
        for k in 0..<(n * n) where valid[k] {
            var v = smoothN[k]
            if simd_dot(v, SIMD3(normals[k].x, normals[k].y, normals[k].z)) < 0 { v = -v }
            v = simd_length(v) > 0 ? simd_normalize(v) : SIMD3(0, 0, 1)
            normals[k] = SCNVector3(v.x, v.y, v.z)
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals),
                                             SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = "creamLayer"
        return node
    }

    // MARK: - Dollops, crumbs, drips

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

    /// A drip: a thin run of cream ending in a heavier bead.
    static func drip() -> SCNNode {
        let node = SCNNode()
        let run = SCNNode(geometry: SCNCone(topRadius: 0.07, bottomRadius: 0.04, height: 0.3))
        run.geometry?.materials = [dripMaterial]
        run.position = SCNVector3(0, -0.15, 0)
        node.addChildNode(run)
        let bead = SCNNode(geometry: SCNSphere(radius: 0.055))
        bead.geometry?.materials = [dripMaterial]
        bead.scale = SCNVector3(1, 1.25, 0.8)
        bead.position = SCNVector3(0, -0.3, 0)
        node.addChildNode(bead)
        return node
    }

    /// Soft cream flecks for the splash burst (a fuzzy blob, not a hard dot).
    static let fleckImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
        let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.85).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
        ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }
}
