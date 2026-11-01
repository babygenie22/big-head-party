import UIKit

/// Fine hair strands combed down from the crown. Drawn over flat hair colour so the top and
/// back of the head read as hair rather than paint.
enum HairStrands {
    /// `region` is in texture pixels (top-left origin).
    static func draw(in ctx: CGContext, color: UIColor, region: CGPath, count: Int, rng: inout SeededRandom,
                     size T: CGFloat = FaceLayout.textureSize) {
        let px = T / 1024   // stroke sizes were tuned at 1024²
        let c = color.rgba
        ctx.saveGState()
        ctx.addPath(region)
        ctx.clip()
        ctx.setLineCap(.round)
        for _ in 0..<count {
            let u = rng.next(), v = rng.next() * 0.72
            // Combed out from the crown on top; straight down on the sides and back, which the
            // outer columns of the texture wrap around (radial strands there read as streaks).
            let side = min(max((abs(u - 0.5) - 0.26) / 0.06, 0), 1)
            let dx = (u - 0.5) * (1 - side), dy = (v + 0.2) * (1 - side) + side, len = max(hypot(dx, dy), 0.001)
            let length = (0.015 + rng.next() * 0.045) * T
            let f = 0.6 + rng.next() * 0.8
            let t = min(max((v - 0.56) / 0.14, 0), 1)
            // Fade out at u → 0 / 1, where the two mirrored halves meet at the back of the head.
            let seam = min(min(u, 1 - u) / 0.07, 1)
            let fade = (1 - t * t * (3 - 2 * t)) * seam
            ctx.setStrokeColor(UIColor(red: min(c.r * f, 1), green: min(c.g * f, 1), blue: min(c.b * f, 1), alpha: 0.32 * fade).cgColor)
            ctx.setLineWidth((1 + rng.next() * 2.2) * px)
            ctx.move(to: CGPoint(x: u * T, y: v * T))
            ctx.addLine(to: CGPoint(x: u * T + dx / len * length + (rng.next() - 0.5) * 6 * px, y: v * T + dy / len * length))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
