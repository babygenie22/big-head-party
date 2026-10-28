import SceneKit
import simd

/// Blend-shape targets every head supports. They are what make a hit *read* on a face:
/// a pie flattens it, a hook shoves the cheeks sideways, a scream drops the jaw.
enum Morph: String, CaseIterable {
    case squish, mouthOpen, puff, skewLeft, skewRight
}

/// Sculpts a 3D head mesh for a `FaceShape`.
///
/// The head is built as a stack of horizontal elliptical rings (skull on top, jaw below).
/// The jaw rings follow the person's measured jawline; on the front of the face a relief
/// field adds brow ridge, eye sockets, cheekbones, nose, lips and chin *at the person's own
/// landmark positions*. Texture coordinates come from a frontal projection that exactly
/// matches the aligned face texture, so the photo's nose sits on the mesh's nose.
///
/// The model is ~2.1 units wide and ~2.4 tall, centered near the origin, facing +Z.
enum HeadMeshBuilder {
    /// Half-extent of the face texture in model units: u = 0.5 + x / (2S).
    static let S: Float = 1.5
    /// Model Y at the vertical center of the texture.
    static let yCenter: Float = -0.2
    static let craniumRings = 54
    static let jawRings = 70
    static let segments = 104
    static let topY: Float = 1.28

    static func modelY(v: CGFloat) -> Float { yCenter + (0.5 - Float(v)) * 2 * S }
    static func modelX(u: CGFloat) -> Float { (Float(u) - 0.5) * 2 * S }

    struct Output {
        let geometry: SCNGeometry
        let morphTargets: [SCNGeometry]
        /// Handy anchor points (model space) for hats, cream splats and particle effects.
        let foreheadY: Float
        let eyeY: Float
        let noseTip: SCNVector3
        let mouth: SCNVector3
        let chinY: Float
    }

    static func build(shape rawShape: FaceShape) -> Output {
        let shape = FaceLayout.sanitized(rawShape)
        let eyeV = Float(shape.eyeLineV)
        let chinV = Float(shape.chin.y)
        let midU = Float(shape.midlineU)
        let yEye = modelY(v: shape.eyeLineV)
        let yChin = modelY(v: shape.chin.y)

        // Jaw half-width as a function of s (0 = eye line, 1 = chin), from the measured contour.
        // Each side of the jawline is interpolated separately (piecewise-linear, no ripples),
        // then the two sides are averaged so the head stays symmetric.
        var leftSide: [(s: Float, w: Float)] = [], rightSide: [(s: Float, w: Float)] = []
        for p in shape.contour {
            let s = (Float(p.y) - eyeV) / max(chinV - eyeV, 0.05)
            let dx = (Float(p.x) - midU) * 2 * S
            if dx <= 0.05 { leftSide.append((s, -dx)) }
            if dx >= -0.05 { rightSide.append((s, dx)) }
        }
        func interpolate(_ side: [(s: Float, w: Float)], _ s: Float) -> Float {
            let pts = (side + [(1, 0)]).sorted { $0.s < $1.s }
            guard let first = pts.first else { return 0.9 }
            if s <= first.s { return max(first.w, 0) }
            for k in 1..<pts.count where s <= pts[k].s {
                let a = pts[k - 1], b = pts[k]
                let t = (s - a.s) / max(b.s - a.s, 1e-4)
                return max(0, a.w + (b.w - a.w) * t)
            }
            return 0
        }
        func contourHalfWidth(_ s: Float) -> Float {
            (interpolate(leftSide, s) + interpolate(rightSide, s)) / 2
        }
        let templeW = simd_clamp(contourHalfWidth(0.05) * 1.08, 0.85, 1.18)

        struct Ring { var y: Float; var w: Float; var cz: Float; var front: Float; var back: Float }
        var rings: [Ring] = []

        // Skull: quarter-ellipse from the crown down to the eye line.
        for k in 0...craniumRings {
            let psi = Float.pi / 2 * (1 - Float(k) / Float(craniumRings))   // π/2 at the crown → 0 at the eyes
            let c = cos(psi)
            rings.append(Ring(y: yEye + (topY - yEye) * sin(psi),
                              w: templeW * pow(c, 0.8),
                              cz: -0.05,
                              front: 1.0 * pow(c, 0.85),
                              back: 1.15 * pow(c, 0.7)))
        }
        // Jaw: eye line down to the chin, following the person's jawline.
        var jawWidths: [Float] = (1...jawRings).map { k in
            let s = Float(k) / Float(jawRings)
            return lerp(templeW, contourHalfWidth(s) * 1.05, t: smoothStep(0, 0.35, s))
        }
        for _ in 0..<4 {   // light smoothing so the jaw reads as one clean curve
            var next = jawWidths
            for k in 1..<(jawWidths.count - 1) { next[k] = (jawWidths[k - 1] + 2 * jawWidths[k] + jawWidths[k + 1]) / 4 }
            jawWidths = next
        }
        for k in 1...jawRings {
            let s = Float(k) / Float(jawRings)
            // Never narrower than a rounded chin, so the jaw ends in a U rather than a point.
            let tc = simd_clamp((s - 0.8) / 0.2, 0, 1)
            let w = max(jawWidths[k - 1], 0.30 * sqrt(max(0, 1 - tc * tc)))
            let narrow = sqrt(min(1, w / 0.45))
            let e = pow(s, 1.6)
            rings.append(Ring(y: yEye + (yChin - yEye) * s,
                              w: w,
                              cz: lerp(-0.05, 0.45, t: e),
                              front: lerp(1.0, 0.32, t: e) * narrow,
                              back: lerp(1.15, 0.30, t: pow(s, 1.2)) * narrow))
        }

        let cols = segments + 1
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var frontWeights: [Float] = []
        var centerZ: [Float] = []
        positions.reserveCapacity(rings.count * cols)

        for ring in rings {
            for j in 0..<cols {
                let a = -Float.pi + 2 * Float.pi * Float(j) / Float(segments)
                let ca = cos(a), sa = sin(a)
                let x = ring.w * sa
                var z = ring.cz + (ca >= 0 ? ring.front : ring.back) * ca
                let y = ring.y
                let uFront = 0.5 + x / (2 * S)
                let v = 0.5 - (y - yCenter) / (2 * S)
                let fw = pow(max(0, ca), 1.5)
                if fw > 0 {
                    z += relief(u: uFront, v: v, shape: shape) * fw
                }
                // Expressions only move the face, not the crown.
                let faceBand = 1 - smoothStep(yEye + 0.5, yEye + 1.0, y)
                let u: Float
                if ca >= 0 {
                    u = uFront
                } else {
                    // Back of the head samples the texture's outer margin (hair/skin fill) so the
                    // face is never mirrored onto the back. Continuous with the front at the sides.
                    let side: Float = (sa > 0 || (sa == 0 && a > 0)) ? 1 : -1
                    let edge = ring.w / (2 * S)
                    u = 0.5 + side * (edge + (0.49 - edge) * (-ca))
                }
                positions.append(SIMD3(x, y, z))
                uvs.append(SIMD2(u, simd_clamp(v, 0.005, 0.995)))
                frontWeights.append(fw * faceBand)
                centerZ.append(ring.cz)
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity((rings.count - 1) * segments * 6)
        for i in 0..<(rings.count - 1) {
            for j in 0..<segments {
                let a = UInt32(i * cols + j)
                let b = UInt32((i + 1) * cols + j)
                let c = a + 1
                let d = b + 1
                indices += [a, b, c, c, b, d]
            }
        }

        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let uvSource = SCNGeometrySource(textureCoordinates: uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })

        func makeGeometry(_ pts: [SIMD3<Float>], withUV: Bool) -> SCNGeometry {
            let normals = computeNormals(pts, indices: indices, cols: cols, rows: rings.count)
            var sources = [SCNGeometrySource(vertices: pts.map { SCNVector3($0.x, $0.y, $0.z) }),
                           SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })]
            if withUV { sources.append(uvSource) }
            return SCNGeometry(sources: sources, elements: [element])
        }

        let base = makeGeometry(positions, withUV: true)

        // ---- Blend shapes -------------------------------------------------------------
        let mouthY = modelY(v: shape.mouthCenter.y)
        let cheekY = modelY(v: shape.mouthCenter.y - 0.05)
        let faceMidY = (yEye + yChin) / 2
        var targets: [SCNGeometry] = []
        for morph in Morph.allCases {
            var pts = positions
            for idx in pts.indices {
                let p = positions[idx]
                let fw = frontWeights[idx]
                var q = p
                switch morph {
                case .squish:
                    // Pancake: face pushed back, widened a touch.
                    q.z = centerZ[idx] + (p.z - centerZ[idx]) * (1 - 0.45 * fw)
                    q.x = p.x * (1 + 0.12 * fw)
                    q.y = p.y + (p.y - faceMidY) * 0.05 * fw
                case .mouthOpen:
                    // Whole jaw drops below the mouth line; lips and cheeks stretch.
                    let drop = smoothStep(mouthY + 0.02, mouthY - 0.14, p.y)
                    let lateral = max(0, 1 - pow(abs(p.x) / 1.05, 4))
                    q.y = p.y - 0.32 * drop * lateral
                    q.z = p.z + 0.05 * drop * fw
                case .puff:
                    for side: Float in [-1, 1] {
                        let dx = p.x - side * 0.5, dy = p.y - cheekY
                        let g = exp(-(dx * dx + dy * dy) / (2 * 0.3 * 0.3))
                        q.x += side * 0.22 * g * fw
                        q.z += 0.14 * g * fw
                    }
                case .skewLeft, .skewRight:
                    let dir: Float = morph == .skewLeft ? -1 : 1
                    let band = exp(-pow((p.y - faceMidY) / 0.75, 2))
                    q.x = p.x + dir * 0.30 * fw * fw * band
                    // The cheek that got hit flattens.
                    let hitSide = max(0, -dir * p.x)
                    q.z = p.z - 0.18 * fw * hitSide * band
                }
                pts[idx] = q
            }
            let g = makeGeometry(pts, withUV: false)
            g.name = morph.rawValue
            targets.append(g)
        }

        let noseX = modelX(u: shape.noseTip.x), noseY = modelY(v: shape.noseTip.y)
        let mouthX = modelX(u: shape.mouthCenter.x)
        return Output(geometry: base,
                      morphTargets: targets,
                      foreheadY: yEye + 0.45,
                      eyeY: yEye,
                      noseTip: SCNVector3(noseX, noseY, 0.95 + 0.27),
                      mouth: SCNVector3(mouthX, mouthY, 0.92),
                      chinY: yChin)
    }

    // MARK: - Facial relief

    private static func g2(_ u: Float, _ v: Float, _ cu: Float, _ cv: Float, _ su: Float, _ sv: Float) -> Float {
        let du = (u - cu) / su, dv = (v - cv) / sv
        return exp(-0.5 * (du * du + dv * dv))
    }

    /// Height field (model units, +Z = toward the viewer) for the front of the face.
    static func relief(u: Float, v: Float, shape: FaceShape) -> Float {
        let lx = Float(shape.leftEye.x), ly = Float(shape.leftEye.y)
        let rx = Float(shape.rightEye.x), ry = Float(shape.rightEye.y)
        let eyeU = (lx + rx) / 2, eyeV = (ly + ry) / 2
        let nx = Float(shape.noseTip.x), ny = Float(shape.noseTip.y)
        let mx = Float(shape.mouthCenter.x), my = Float(shape.mouthCenter.y)
        let mw = Float(shape.mouthWidth)
        let cx = Float(shape.chin.x), cy = Float(shape.chin.y)

        var z: Float = 0
        // Eye sockets, then the eyeballs inside them.
        z -= 0.11 * g2(u, v, lx, ly, 0.055, 0.035)
        z -= 0.11 * g2(u, v, rx, ry, 0.055, 0.035)
        z += 0.05 * g2(u, v, lx, ly, 0.028, 0.017)
        z += 0.05 * g2(u, v, rx, ry, 0.028, 0.017)
        // Brow ridge.
        z += 0.07 * g2(u, v, lx, ly - 0.065, 0.07, 0.025)
        z += 0.07 * g2(u, v, rx, ry - 0.065, 0.07, 0.025)
        // Nose: a ridge from between the eyes down to the tip, getting taller and wider.
        let noseLen = max(ny - eyeV, 0.05)
        let t = simd_clamp((v - eyeV) / noseLen, 0, 1)
        let ridgeU = eyeU + (nx - eyeU) * t
        let sigma = 0.024 + 0.026 * t
        var ridge = (0.05 + 0.15 * pow(t, 1.4)) * exp(-0.5 * pow((u - ridgeU) / sigma, 2))
        if v < eyeV - 0.03 { ridge *= exp(-0.5 * pow((v - (eyeV - 0.03)) / 0.02, 2)) }
        if v > ny { ridge *= exp(-0.5 * pow((v - ny) / 0.016, 2)) }
        z += ridge
        z += 0.07 * g2(u, v, nx, ny - 0.008, 0.03, 0.024)                  // tip
        z += 0.05 * g2(u, v, nx - 0.04, ny + 0.002, 0.02, 0.018)          // nostril wings
        z += 0.05 * g2(u, v, nx + 0.04, ny + 0.002, 0.02, 0.018)
        // Lips and the line between them.
        z += 0.07 * g2(u, v, mx, my, mw * 0.5, 0.024)
        z -= 0.03 * g2(u, v, mx, my, mw * 0.45, 0.006)
        // Cheekbones.
        z += 0.05 * g2(u, v, lx - 0.02, eyeV + 0.10, 0.06, 0.05)
        z += 0.05 * g2(u, v, rx + 0.02, eyeV + 0.10, 0.06, 0.05)
        // Chin.
        z += 0.07 * g2(u, v, cx, cy - 0.045, 0.06, 0.035)
        return z
    }

    // MARK: - Helpers

    private static func computeNormals(_ pts: [SIMD3<Float>], indices: [UInt32], cols: Int, rows: Int) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: pts.count)
        var i = 0
        while i < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            let n = cross(pts[b] - pts[a], pts[c] - pts[a])
            normals[a] += n; normals[b] += n; normals[c] += n
            i += 3
        }
        // The seam column is duplicated (u wraps), so share normals across it.
        for r in 0..<rows {
            let first = r * cols, last = r * cols + cols - 1
            let sum = normals[first] + normals[last]
            normals[first] = sum; normals[last] = sum
        }
        for k in normals.indices {
            let len = simd_length(normals[k])
            if len > 1e-8 {
                normals[k] /= len
            } else {
                normals[k] = pts[k].y > 0 ? SIMD3(0, 1, 0) : SIMD3(0, -0.6, 0.8)
            }
        }
        return normals
    }
}

@inline(__always) func lerp(_ a: Float, _ b: Float, t: Float) -> Float { a + (b - a) * t }

@inline(__always) func smoothStep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = simd_clamp((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)
}
