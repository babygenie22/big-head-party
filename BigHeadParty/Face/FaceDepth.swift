import AVFoundation
import ImageIO
import UIKit

/// The real shape of a face, measured: distance from the camera in meters for each point of the
/// photo. Comes from the TrueDepth selfie camera or from a Portrait-mode photo, which stores its
/// depth beside the picture. Upright like the photo, top-left origin, at depth-map resolution
/// (about 640×480). Zero where the camera couldn't tell.
struct FaceDepth {
    let width: Int
    let height: Int
    let meters: [Float]

    /// Depth stored inside a photo file (HEIC/JPEG from the camera or a Portrait photo), if any.
    static func read(from data: Data) -> FaceDepth? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDisparity)
            ?? CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDepth)
        guard let info = info as? [AnyHashable: Any], var depth = try? AVDepthData(fromDictionaryRepresentation: info) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if let raw = props?[kCGImagePropertyOrientation] as? UInt32, let orientation = CGImagePropertyOrientation(rawValue: raw) {
            depth = depth.applyingExifOrientation(orientation)
        }
        return FaceDepth(depth)
    }

    init?(_ data: AVDepthData) {
        let depth = data.depthDataType == kCVPixelFormatType_DepthFloat32 ? data : data.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = depth.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let w = CVPixelBufferGetWidth(map), h = CVPixelBufferGetHeight(map), row = CVPixelBufferGetBytesPerRow(map)
        var values = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let line = base.advanced(by: y * row).assumingMemoryBound(to: Float32.self)
            for x in 0..<w {
                let d = line[x]
                values[y * w + x] = d.isFinite && d > 0.05 && d < 3 ? d : 0
            }
        }
        self.init(width: w, height: h, meters: values)
    }

    init(width: Int, height: Int, meters: [Float]) {
        self.width = width
        self.height = height
        self.meters = meters
    }

    /// Depth at a point of the photo (0...1, top-left origin), blended from the four nearest
    /// samples that are known. Nil where none are.
    func sample(x: CGFloat, y: CGFloat) -> Float? {
        let fx = Float(x) * Float(width) - 0.5, fy = Float(y) * Float(height) - 0.5
        let x0 = Int(floor(fx)), y0 = Int(floor(fy))
        let tx = fx - Float(x0), ty = fy - Float(y0)
        var sum: Float = 0, weight: Float = 0
        for (dx, dy, w) in [(0, 0, (1 - tx) * (1 - ty)), (1, 0, tx * (1 - ty)), (0, 1, (1 - tx) * ty), (1, 1, tx * ty)] {
            let px = x0 + dx, py = y0 + dy
            guard px >= 0, py >= 0, px < width, py < height else { continue }
            let d = meters[py * width + px]
            guard d > 0 else { continue }
            sum += d * w; weight += w
        }
        return weight > 0.05 ? sum / weight : nil
    }

    #if DEBUG
    /// Simulator testing (`-studioTestDepth path`): two little-endian Int32s (width, height),
    /// then that many Float32 meters, row by row from the top.
    static func debugLoad(_ path: String) -> FaceDepth? {
        guard let data = FileManager.default.contents(atPath: path), data.count > 8 else { return nil }
        return data.withUnsafeBytes { raw -> FaceDepth? in
            let w = Int(raw.loadUnaligned(fromByteOffset: 0, as: Int32.self)), h = Int(raw.loadUnaligned(fromByteOffset: 4, as: Int32.self))
            guard w > 0, h > 0, data.count >= 8 + w * h * 4 else { return nil }
            let values = (0..<(w * h)).map { raw.loadUnaligned(fromByteOffset: 8 + $0 * 4, as: Float32.self) }
            return FaceDepth(width: w, height: h, meters: values)
        }
    }
    #endif
}

/// Turns measured depth into the face relief the head mesh uses (see `FaceShape.depthRelief`).
enum DepthRelief {
    static let size = 96
    /// Model units per meter: the eyes sit 0.28 of the texture apart (0.84 model units), and
    /// real pupils are about 63 mm apart.
    static let unitsPerMeter: Float = 0.84 / 0.063

    /// `photoPoint` maps texture uv to the photo (0...1, top-left origin). Nil when the depth
    /// doesn't cover the face well enough to trust.
    static func build(depth: FaceDepth, shape: FaceShape, photoPoint: (CGPoint) -> CGPoint) -> [Float]? {
        let n = size
        let midU = Float(shape.midlineU)
        let cv: Float = 0.47, ru: Float = 0.3, rv: Float = 0.38
        func ellipse(_ i: Int, _ j: Int) -> Float {
            let u = (Float(i) + 0.5) / Float(n), v = (Float(j) + 0.5) / Float(n)
            let du = (u - midU) / ru, dv = (v - cv) / rv
            return sqrt(du * du + dv * dv)
        }
        var raw = [Float](repeating: 0, count: n * n)
        var known = [Bool](repeating: false, count: n * n)
        var faceDepths: [Float] = []
        var faceCells = 0
        for j in 0..<n {
            for i in 0..<n {
                let uv = CGPoint(x: (CGFloat(i) + 0.5) / CGFloat(n), y: (CGFloat(j) + 0.5) / CGFloat(n))
                let p = photoPoint(uv)
                let inFace = ellipse(i, j) < 0.8
                if inFace { faceCells += 1 }
                guard p.x >= 0, p.y >= 0, p.x <= 1, p.y <= 1, let d = depth.sample(x: p.x, y: p.y) else { continue }
                raw[j * n + i] = d
                known[j * n + i] = true
                if inFace { faceDepths.append(d) }
            }
        }
        guard faceCells > 0, Float(faceDepths.count) > Float(faceCells) * 0.6 else { return nil }
        // The face's own plane: its median depth. Height is how far each point stands out of it.
        let reference = faceDepths.sorted()[faceDepths.count / 2]
        var height = [Float](repeating: 0, count: n * n)
        for k in 0..<(n * n) where known[k] {
            let h = reference - raw[k]
            if h > -0.06 && h < 0.09 { height[k] = h } else { known[k] = false }   // hair, hands, background
        }
        // Keep the features (nose, sockets, lips, brows, chin) and leave the overall roundness to
        // the head mesh: subtract a wide blur of the face.
        let broad = blur(height, known: known, n: n, radius: 9, passes: 3)
        var relief = [Float](repeating: 0, count: n * n)
        for j in 0..<n {
            for i in 0..<n {
                let k = j * n + i
                guard known[k] else { continue }
                let e = ellipse(i, j)
                let r = height[k] - broad[k]
                // Dips are features only well inside the face (eye sockets, the line of the lips);
                // nearer the edge they're just the cheeks curving away, which the mesh already does.
                let fade = r < 0 ? 1 - smooth01((e - 0.55) / 0.25) : 1 - smooth01((e - 0.85) / 0.2)
                relief[k] = r * unitsPerMeter * fade
            }
        }
        relief = blur(relief, known: [Bool](repeating: true, count: n * n), n: n, radius: 1, passes: 1)
        // A face with no relief at all (a flat photo of a photo, a bad map) isn't worth using.
        let nose = relief[Int(shape.noseTip.y * CGFloat(n)) * n + Int(shape.noseTip.x * CGFloat(n))]
        guard nose > 0.08 else { return nil }
        return relief.map { min(max($0, -0.2), 0.45) }
    }

    /// Bilinear lookup in a relief grid at texture (u, v).
    static func value(_ grid: [Float], u: Float, v: Float) -> Float {
        let n = size
        let fx = u * Float(n) - 0.5, fy = v * Float(n) - 0.5
        let x0 = max(0, min(n - 2, Int(floor(fx)))), y0 = max(0, min(n - 2, Int(floor(fy))))
        let tx = max(0, min(1, fx - Float(x0))), ty = max(0, min(1, fy - Float(y0)))
        let a = grid[y0 * n + x0], b = grid[y0 * n + x0 + 1], c = grid[(y0 + 1) * n + x0], d = grid[(y0 + 1) * n + x0 + 1]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    }

    private static func smooth01(_ t: Float) -> Float {
        let x = max(0, min(1, t))
        return x * x * (3 - 2 * x)
    }

    /// Box blur over known cells only (unknown cells take their neighbors' average), repeated to
    /// approximate a Gaussian.
    private static func blur(_ values: [Float], known: [Bool], n: Int, radius: Int, passes: Int) -> [Float] {
        var v = values, w = known.map { $0 ? Float(1) : 0 }
        for k in v.indices { v[k] *= w[k] }
        for _ in 0..<passes {
            for horizontal in [true, false] {
                var nv = v, nw = w
                for j in 0..<n {
                    for i in 0..<n {
                        var sv: Float = 0, sw: Float = 0
                        for o in -radius...radius {
                            let x = horizontal ? i + o : i, y = horizontal ? j : j + o
                            guard x >= 0, y >= 0, x < n, y < n else { continue }
                            sv += v[y * n + x]; sw += w[y * n + x]
                        }
                        let c = Float(2 * radius + 1)
                        nv[j * n + i] = sv / c; nw[j * n + i] = sw / c
                    }
                }
                v = nv; w = nw
            }
        }
        return zip(v, w).map { $1 > 1e-4 ? $0 / $1 : 0 }
    }
}
