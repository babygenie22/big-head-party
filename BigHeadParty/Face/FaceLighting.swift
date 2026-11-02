import CoreImage
import simd

extension FaceTextureBuilder {
    /// Takes the photo's sideways light off the face, so the game's lights can do the lighting:
    /// a window to one side leaves one cheek bright and the other in shadow, and that shadow then
    /// stays painted on the head whichever way it turns.
    ///
    /// Faces are close to symmetric, so how much brighter each point of skin is than its mirror
    /// point across the nose is mostly the light, not the skin. That difference is fitted against
    /// how far each point faces sideways (from the face's shape: measured depth if we have it,
    /// otherwise a rounded face), and divided back out. Light from above and the front stays, so
    /// faces keep their natural modelling. `photo` is already aligned to texture space.
    static func evenLighting(_ photo: CIImage, shape: FaceShape, canvas: CGRect) -> CIImage {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "noEvenLighting") { return photo }   // before/after checks
        #endif
        let n = 64
        var px = [Float](repeating: 0, count: n * n * 4)
        let small = photo.transformed(by: CGAffineTransform(scaleX: CGFloat(n) / canvas.width, y: CGFloat(n) / canvas.height))
        ciContext.render(small, toBitmap: &px, rowBytes: n * 16, bounds: CGRect(x: 0, y: 0, width: n, height: n),
                         format: .RGBAf, colorSpace: nil)

        let midU = Float(shape.midlineU), eyeV = Float(shape.eyeLineV)
        let cv: Float = 0.47, ru: Float = 0.29, rv: Float = 0.37
        // Normal at texture (u, v); +x right, +y up, +z toward the camera.
        func normal(_ u: Float, _ v: Float) -> SIMD3<Float>? {
            let x = (u - midU) / ru, y = (cv - v) / rv
            let r2 = x * x + y * y
            guard r2 < 1 else { return nil }
            var nrm = SIMD3(x * 0.9, y * 0.9, sqrt(max(0.05, 1 - r2)))
            if let grid = shape.depthRelief {
                // Slopes of the measured relief (model units over model units: 3 per texture unit).
                let e: Float = 1.5 / Float(DepthRelief.size)
                let gx = (DepthRelief.value(grid, u: u + e, v: v) - DepthRelief.value(grid, u: u - e, v: v)) / (2 * e * 3)
                let gy = (DepthRelief.value(grid, u: u, v: v - e) - DepthRelief.value(grid, u: u, v: v + e)) / (2 * e * 3)
                nrm += SIMD3(-gx, -gy, 0) * nrm.z
            }
            return simd_normalize(nrm)
        }
        func isSkin(_ u: Float, _ v: Float) -> Bool {
            // Leave out eyes, brows and mouth: they're dark because of what they are, not the light.
            for ex in [Float(shape.leftEye.x), Float(shape.rightEye.x)] {
                if abs(u - ex) < 0.085 && v > eyeV - 0.1 && v < eyeV + 0.045 { return false }
            }
            let mx = Float(shape.mouthCenter.x), my = Float(shape.mouthCenter.y), mw = Float(shape.mouthWidth)
            if abs(u - mx) < mw * 0.6 + 0.02 && abs(v - my) < 0.05 { return false }
            return v > eyeV - 0.2   // below the hairline, roughly
        }

        // Bitmap rows run top to bottom, like v.
        func luminance(_ col: Int, _ row: Int) -> Float {
            let k = (row * n + col) * 4
            return 0.2126 * px[k] + 0.7152 * px[k + 1] + 0.0722 * px[k + 2]
        }
        // Pairs of mirrored skin points: (how far right the right one faces, log brightness ratio).
        var pairs: [(x: Float, d: Float)] = []
        for row in 0..<n {
            for col in 0..<n {
                let u = (Float(col) + 0.5) / Float(n), v = (Float(row) + 0.5) / Float(n)
                guard u > midU + 0.03 else { continue }
                let mu = 2 * midU - u
                let mcol = Int(mu * Float(n))
                guard mcol >= 0, mcol < n, isSkin(u, v), isSkin(mu, v),
                      let nr = normal(u, v), let nl = normal(mu, v), nr.z > 0.3, nl.z > 0.3 else { continue }
                let lr = luminance(col, row), ll = luminance(mcol, row)
                guard lr > 0.005, ll > 0.005 else { continue }
                pairs.append((nr.x - nl.x, log(lr / ll)))
            }
        }
        guard pairs.count > 100 else { return photo }
        // Brightness ≈ exp(k · nx): fit k, then refit without the worst-fitting fifth (a mole,
        // stubble, a glasses arm, a strand of hair on one side only).
        func fit(_ set: [(x: Float, d: Float)]) -> Float {
            let sxx = set.reduce(0) { $0 + $1.x * $1.x }, sxd = set.reduce(0) { $0 + $1.x * $1.d }
            return sxx > 1e-6 ? sxd / sxx : 0
        }
        var k = fit(pairs)
        for _ in 0..<2 {
            let residuals = pairs.map { abs($0.d - k * $0.x) }
            let cut = residuals.sorted()[pairs.count * 8 / 10]
            k = fit(zip(pairs, residuals).filter { $0.1 <= cut }.map(\.0))
        }
        // Already evenly lit: nothing to do.
        guard abs(k) > 0.05 else { return photo }

        var gain = [Float](repeating: 1, count: n * n * 4)
        for row in 0..<n {
            for col in 0..<n {
                let u = (Float(col) + 0.5) / Float(n), v = (Float(row) + 0.5) / Float(n)
                // Past the face, the same light carries on over the ears and hair.
                let nx = normal(u, v)?.x ?? min(max((u - midU) / ru * 0.9, -0.9), 0.9)
                // Mostly, not fully: a hint of the original light keeps it looking like a photo.
                let g = min(max(exp(-0.85 * k * nx), 0.65), 1.6)
                let i = (row * n + col) * 4
                gain[i] = g; gain[i + 1] = g; gain[i + 2] = g
            }
        }
        let gainImage = gain.withUnsafeBytes { bytes in
            CIImage(bitmapData: Data(bytes), bytesPerRow: n * 16, size: CGSize(width: n, height: n), format: .RGBAf, colorSpace: nil)
        }
        let smooth = gainImage
            .transformed(by: CGAffineTransform(scaleX: canvas.width / CGFloat(n), y: canvas.height / CGFloat(n)))
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: canvas.width * 0.02])
            .cropped(to: canvas)
        return smooth.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: photo])
    }
}
