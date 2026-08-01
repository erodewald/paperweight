import SwiftUI

/// "The screen is claimed at its corners."
///
/// Each sprig is one quadratic Bézier stem that draws itself in, then sprouts
/// tapered leaflets in order along its length. Back groups sit dimmer and sway
/// less than the front ones, which is the whole depth cue.
struct OvergrownScene: View {
    var lock: Double = 1
    var time: Double = 0

    /// A single frond. `slot` is its place in the 11-step crawl order.
    private struct Sprig {
        let p0: CGPoint, p1: CGPoint, p2: CGPoint
        let leaflets: Int
        let size: CGFloat
        let slot: Int
        let phase: Double
        let flip: CGFloat
        let colors: [Color]
        let stem: Color
        let bud: Bool
    }

    private static let topRightSize = CGSize(width: 480, height: 400)
    private static let bottomLeftSize = CGSize(width: 340, height: 260)

    private static let topRightBack: [Sprig] = [
        Sprig(p0: .init(x: 484, y: -8), p1: .init(x: 370, y: 60), p2: .init(x: 250, y: 180),
              leaflets: 11, size: 21, slot: 0, phase: 0.5, flip: 1,
              colors: [PW.treeMid, PW.bush], stem: PW.trunk, bud: false),
        Sprig(p0: .init(x: 476, y: 40), p1: .init(x: 430, y: 180), p2: .init(x: 400, y: 320),
              leaflets: 9, size: 18, slot: 1, phase: 2.8, flip: -1,
              colors: [PW.treeMid, PW.bush], stem: PW.trunk, bud: false),
        Sprig(p0: .init(x: 460, y: 220), p1: .init(x: 370, y: 280), p2: .init(x: 260, y: 330),
              leaflets: 9, size: 16, slot: 2, phase: 4.6, flip: 1,
              colors: [PW.bush, PW.treeMid], stem: PW.trunk, bud: false),
    ]

    private static let topRightFront: [Sprig] = [
        Sprig(p0: .init(x: 482, y: -4), p1: .init(x: 400, y: 40), p2: .init(x: 300, y: 120),
              leaflets: 12, size: 17, slot: 3, phase: 0, flip: 1,
              colors: [PW.treeFront, PW.moss], stem: PW.stem, bud: true),
        Sprig(p0: .init(x: 472, y: 0), p1: .init(x: 452, y: 120), p2: .init(x: 430, y: 244),
              leaflets: 10, size: 14, slot: 4, phase: 2.1, flip: -1,
              colors: [PW.moss, PW.mossLight], stem: PW.stem, bud: true),
        Sprig(p0: .init(x: 446, y: 152), p1: .init(x: 372, y: 202), p2: .init(x: 292, y: 240),
              leaflets: 8, size: 12, slot: 5, phase: 4.0, flip: 1,
              colors: [PW.mossLight, PW.moss], stem: PW.stem, bud: true),
        Sprig(p0: .init(x: 462, y: 58), p1: .init(x: 420, y: 84), p2: .init(x: 376, y: 106),
              leaflets: 5, size: 9, slot: 6, phase: 1.1, flip: -1,
              colors: [PW.mossLight, PW.sage], stem: PW.stem, bud: true),
        Sprig(p0: .init(x: 474, y: 262), p1: .init(x: 400, y: 312), p2: .init(x: 310, y: 346),
              leaflets: 8, size: 12, slot: 7, phase: 5.2, flip: -1,
              colors: [PW.moss, PW.treeFront], stem: PW.stem, bud: true),
    ]

    private static let bottomLeftBack: [Sprig] = [
        Sprig(p0: .init(x: -8, y: 266), p1: .init(x: 90, y: 258), p2: .init(x: 204, y: 240),
              leaflets: 9, size: 15, slot: 8, phase: 3.9, flip: -1,
              colors: [PW.treeMid, PW.bush], stem: PW.trunk, bud: false),
    ]

    private static let bottomLeftFront: [Sprig] = [
        Sprig(p0: .init(x: -4, y: 264), p1: .init(x: 70, y: 240), p2: .init(x: 152, y: 192),
              leaflets: 10, size: 13, slot: 9, phase: 1.3, flip: -1,
              colors: [PW.moss, PW.treeFront], stem: PW.stem, bud: true),
        Sprig(p0: .init(x: 0, y: 252), p1: .init(x: 40, y: 192), p2: .init(x: 82, y: 132),
              leaflets: 7, size: 10, slot: 10, phase: 3.3, flip: 1,
              colors: [PW.mossLight, PW.moss], stem: PW.stem, bud: true),
    ]

    var body: some View {
        Canvas { context, size in
            let swayTopRight = PWMotion.sway(at: time, phase: 0.6) * lock
            let swayBottomLeft = PWMotion.sway(at: time, phase: 3.1) * lock

            // Top-right cluster, anchored to the top-right corner.
            var topRight = context
            topRight.translateBy(x: size.width - Self.topRightSize.width, y: 0)
            draw(&topRight, Self.topRightBack, opacity: 0.85,
                 rotation: swayTopRight * 0.6, about: CGPoint(x: 480, y: 0))
            draw(&topRight, Self.topRightFront, opacity: 1,
                 rotation: swayTopRight, about: CGPoint(x: 480, y: 0))

            // Bottom-left cluster, anchored to the bottom-left corner.
            var bottomLeft = context
            bottomLeft.translateBy(x: 0, y: size.height - Self.bottomLeftSize.height)
            draw(&bottomLeft, Self.bottomLeftBack, opacity: 0.85,
                 rotation: swayBottomLeft * 0.6, about: CGPoint(x: 0, y: 260))
            draw(&bottomLeft, Self.bottomLeftFront, opacity: 1,
                 rotation: swayBottomLeft, about: CGPoint(x: 0, y: 260))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, _ sprigs: [Sprig],
                      opacity: Double, rotation: Double, about pivot: CGPoint) {
        var layer = context
        layer.opacity = opacity
        layer.translateBy(x: pivot.x, y: pivot.y)
        layer.rotate(by: .degrees(rotation))
        layer.translateBy(x: -pivot.x, y: -pivot.y)
        for sprig in sprigs { drawSprig(&layer, sprig) }
    }

    private func drawSprig(_ context: inout GraphicsContext, _ sprig: Sprig) {
        let grown = PWMotion.crawl(index: sprig.slot, count: 11, lock: lock)
        guard grown > 0.001 else { return }

        // The stem draws itself in over the first 70% of the sprig's growth.
        let stemProgress = min(grown / 0.7, 1)
        var stem = Path()
        stem.move(to: sprig.p0)
        stem.addQuadCurve(to: sprig.p2, control: sprig.p1)
        context.stroke(
            stem.trimmedPath(from: 0, to: stemProgress),
            with: .color(sprig.stem),
            style: StrokeStyle(lineWidth: 3, lineCap: .round))

        let slots = max(sprig.leaflets - 1, 1)
        for index in 0..<sprig.leaflets {
            let u = 0.14 + 0.8 * (Double(index) / Double(slots))
            // Leaflets trail the stem tip and pop in order along it.
            let opened = PWMotion.grow(PWMotion.ramp(grown - 0.7 * u, 0, 0.3))
                * min(max((stemProgress - u) * 10, 0), 1)
            guard opened > 0.001 else { continue }

            let point = Self.point(sprig, at: u)
            let angle = Self.tangentDegrees(sprig, at: u)
            let side = (index % 2 == 1 ? 1 : -1) * sprig.flip
            let leafSize = sprig.size * (1 - 0.5 * CGFloat(Double(index) / Double(slots)))

            var leaf = context
            leaf.translateBy(x: point.x, y: point.y)
            leaf.rotate(by: .degrees(angle + Double(side) * 52))
            leaf.scaleBy(x: opened, y: opened)
            leaf.fill(
                Path(ellipseIn: CGRect(x: leafSize * 0.95 - leafSize, y: -leafSize * 0.34,
                                       width: leafSize * 2, height: leafSize * 0.68)),
                with: .color(sprig.colors[index % sprig.colors.count]))
        }

        if sprig.bud {
            let tip = PWMotion.grow(PWMotion.ramp(grown, 0.75, 1))
            let pulse = 0.55 + 0.45 * sin(2 * .pi * time / 4.2 + sprig.phase)
            let radius = sprig.size * 0.42
            context.fill(
                Path(ellipseIn: CGRect(x: sprig.p2.x - radius, y: sprig.p2.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(PW.dawnGlow.opacity(tip * pulse)))
        }
    }

    /// Point on the quadratic Bézier at `u`.
    private static func point(_ sprig: Sprig, at u: Double) -> CGPoint {
        let t = CGFloat(u)
        let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
        return CGPoint(x: a * sprig.p0.x + b * sprig.p1.x + c * sprig.p2.x,
                       y: a * sprig.p0.y + b * sprig.p1.y + c * sprig.p2.y)
    }

    /// Tangent direction on the curve at `u`, in degrees.
    private static func tangentDegrees(_ sprig: Sprig, at u: Double) -> Double {
        let t = CGFloat(u)
        let dx = 2 * (1 - t) * (sprig.p1.x - sprig.p0.x) + 2 * t * (sprig.p2.x - sprig.p1.x)
        let dy = 2 * (1 - t) * (sprig.p1.y - sprig.p0.y) + 2 * t * (sprig.p2.y - sprig.p1.y)
        return atan2(Double(dy), Double(dx)) * 180 / .pi
    }
}
