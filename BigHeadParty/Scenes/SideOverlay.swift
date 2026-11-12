import SceneKit
import UIKit
import simd

/// A side photo worn on the head: a skin-tight layer over that side of the head mesh, textured
/// straight from the photo (each vertex looks up where the side camera saw it) and fading out
/// toward the front, where the front photo is better, and toward the back, which no photo saw.
/// Built on the head's own vertex grid like the cream and the hair, so it follows expressions.
enum SideOverlay {
    private struct Key: Hashable { let head: ObjectIdentifier; let view: SideViewKey }
    private struct SideViewKey: Hashable { let yaw: Float; let a: [Float]; let b: [Float] }
    private static var cache: [Key: (geometry: SCNGeometry, targets: [SCNGeometry])] = [:]
    private static let lock = NSLock()

    static func node(head: SCNGeometry, targets: [SCNGeometry], view: SideView, texture: UIImage) -> SCNNode? {
        let key = Key(head: ObjectIdentifier(head), view: SideViewKey(yaw: view.yaw, a: view.a, b: view.b))
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        guard let mesh = cached ?? sculpt(head: head, targets: targets, view: view) else { return nil }
        if cached == nil {
            lock.lock(); cache[key] = mesh; lock.unlock()
        }
        let geometry = mesh.geometry.copy() as! SCNGeometry
        let m = Fabric.skin(.white)
        m.diffuse.contents = texture
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 16
        // Blended over the head's own skin; it never hides anything in front of it.
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        geometry.materials = [m]
        let node = SCNNode(geometry: geometry)
        node.name = "sideOverlay"
        node.castsShadow = false
        let morpher = SCNMorpher()
        morpher.calculationMode = .additive
        morpher.targets = mesh.targets
        node.morpher = morpher
        return node
    }

    private static func sculpt(head: SCNGeometry, targets: [SCNGeometry], view: SideView) -> (geometry: SCNGeometry, targets: [SCNGeometry])? {
        guard let v = head.sources(for: .vertex).first, let n = head.sources(for: .normal).first, let e = head.elements.first else { return nil }
        let base = v.vectors, normals = n.vectors
        guard base.count == normals.count else { return nil }
        let weights = normals.map { view.weight(normal: $0) }

        // Only the triangles that show any of the photo.
        let all: [UInt32] = e.data.withUnsafeBytes { raw in
            (0..<(e.primitiveCount * 3)).map { i in
                e.bytesPerIndex == 2 ? UInt32(raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self)) : raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
            }
        }
        var indices: [UInt32] = []
        for t in stride(from: 0, to: all.count, by: 3) {
            let (a, b, c) = (Int(all[t]), Int(all[t + 1]), Int(all[t + 2]))
            if weights[a] > 0 || weights[b] > 0 || weights[c] > 0 { indices += [all[t], all[t + 1], all[t + 2]] }
        }
        guard !indices.isEmpty else { return nil }

        // A hair off the skin, so it never fights the head for depth.
        let positions = base.indices.map { k -> SCNVector3 in
            let p = base[k] + normals[k] * 0.006
            return SCNVector3(p.x, p.y, p.z)
        }
        let uvs = base.map { p -> CGPoint in
            let t = view.uv(p)
            return CGPoint(x: CGFloat(t.x), y: CGFloat(t.y))
        }
        // The fade rides on the vertices: white, with the photo's share as alpha.
        var colors = [Float](repeating: 1, count: base.count * 4)
        for k in base.indices { colors[k * 4 + 3] = weights[k] }
        let colorSource = SCNGeometrySource(data: colors.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .color, vectorCount: base.count,
                                            usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) }),
                                             SCNGeometrySource(textureCoordinates: uvs), colorSource],
                                   elements: [element])
        let deltas: [SCNGeometry] = targets.compactMap { t in
            guard let tp = t.sources(for: .vertex).first?.vectors, tp.count == base.count else { return nil }
            let dp = base.indices.map { k -> SCNVector3 in let d = tp[k] - base[k]; return SCNVector3(d.x, d.y, d.z) }
            let g = SCNGeometry(sources: [SCNGeometrySource(vertices: dp),
                                          SCNGeometrySource(normals: [SCNVector3](repeating: SCNVector3Zero, count: dp.count))],
                                elements: [element])
            g.name = t.name
            return g
        }
        return (geometry, deltas)
    }
}
