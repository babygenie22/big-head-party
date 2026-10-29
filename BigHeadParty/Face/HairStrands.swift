import UIKit

/// Fine hair strands combed down from the crown. Drawn over flat hair colour so the top and
/// back of the head read as hair rather than paint.
enum HairStrands {
    /// `region` is in texture pixels (top-left origin).
    static func draw(in ctx: CGContext, color: UIColor, region: CGPath, count: Int, rng: inout SeededRandom) {
        let T = FaceLayout.textureSize
        let c = color.rgba
        ctx.saveGState()
        ctx.addPath(region)
        ctx.clip()
        ctx.setLineCap(.round)
        for _ in 0..<count {
            let u = rng.next(), v = rng.next() * 0.66
            let dx = u - 0.5, dy = v + 0.2, len = max(hypot(dx, dy), 0.001)
            let length = (0.015 + rng.next() * 0.045) * T
            let f = 0.6 + rng.next() * 0.8
            let t = min(max((v - 0.5) / 0.14, 0), 1)
            let fade = 1 - t * t * (3 - 2 * t)
            ctx.setStrokeColor(UIColor(red: min(c.r * f, 1), green: min(c.g * f, 1), blue: min(c.b * f, 1), alpha: 0.32 * fade).cgColor)
            ctx.setLineWidth(1 + rng.next() * 2.2)
            ctx.move(to: CGPoint(x: u * T, y: v * T))
            ctx.addLine(to: CGPoint(x: u * T + dx / len * length + (rng.next() - 0.5) * 6, y: v * T + dy / len * length))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
