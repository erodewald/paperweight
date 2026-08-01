import SwiftUI

/// "A forest sprouts behind the words."
///
/// Drawn in a fixed 780×250 design space with the ground line at y=230, then
/// scaled to whatever the locked Home can spare. `lock` drives the sprouting;
/// `time` drives the sway and the fireflies, which never stop.
struct DioramaScene: View {
    var lock: Double = 1
    var time: Double = 0

    private static let designSize = CGSize(width: 780, height: 250)
    private static let groundY: CGFloat = 230

    /// Pines: x, height, half-width, growth slot.
    private static let pines: [(x: CGFloat, h: CGFloat, w: CGFloat, slot: Int)] = [
        (70, 140, 26, 0), (140, 104, 22, 1), (636, 128, 26, 1), (716, 94, 21, 2),
    ]

    /// Blob trees: x, scale, phase, growth slot, is-near, bears-fruit.
    private static let blobs: [(x: CGFloat, scale: CGFloat, phase: Double, slot: Int, near: Bool, fruit: Bool)] = [
        (250, 1.3, 0.0, 3, false, false),
        (580, 0.8, 2.1, 4, false, false),
        (420, 1.5, 1.1, 6, true,  true),
    ]

    /// Fireflies: x, y, radius, phase, growth slot they wait on.
    private static let flies: [(x: CGFloat, y: CGFloat, r: CGFloat, phase: Double, slot: Int)] = [
        (120, 150, 4.0, 0.0, 6), (330, 110, 3.0, 2.2, 7), (540, 140, 3.5, 4.1, 7),
        (690, 170, 2.6, 1.3, 6), (220,  90, 3.0, 5.3, 7),
    ]

    var body: some View {
        Canvas { context, size in
            let scale = size.width / Self.designSize.width
            context.translateBy(x: 0, y: size.height - Self.designSize.height * scale)
            context.scaleBy(x: scale, y: scale)

            drawGround(&context, y: 256, rx: 470, ry: 50, color: PW.groundBack)
            for pine in Self.pines { drawPine(&context, pine) }
            for blob in Self.blobs where !blob.near { drawBlob(&context, blob) }
            for blob in Self.blobs where blob.near { drawBlob(&context, blob) }
            drawGround(&context, y: 250, rx: 430, ry: 30, color: PW.groundFront)
            for fly in Self.flies { drawFly(&context, fly) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Ground

    private func drawGround(_ context: inout GraphicsContext,
                            y: CGFloat, rx: CGFloat, ry: CGFloat, color: Color) {
        let rect = CGRect(x: 390 - rx, y: y - ry, width: rx * 2, height: ry * 2)
        context.opacity = lock
        context.fill(Path(ellipseIn: rect), with: .color(color))
        context.opacity = 1
    }

    // MARK: Pines

    private func drawPine(_ context: inout GraphicsContext,
                          _ pine: (x: CGFloat, h: CGFloat, w: CGFloat, slot: Int)) {
        let grown = PWMotion.growth(index: pine.slot, count: 8, lock: lock)
        guard grown > 0.001 else { return }

        var path = Path()
        path.move(to: CGPoint(x: -pine.w, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -pine.h))
        path.addLine(to: CGPoint(x: pine.w, y: 0))
        path.closeSubpath()

        var layer = context
        layer.translateBy(x: pine.x, y: Self.groundY)
        layer.scaleBy(x: grown, y: grown)
        // Stroking with the fill colour is what rounds the pine's points.
        layer.fill(path, with: .color(PW.treeDark))
        layer.stroke(path, with: .color(PW.treeDark),
                     style: StrokeStyle(lineWidth: 12, lineJoin: .round))
    }

    // MARK: Blob trees

    private func drawBlob(_ context: inout GraphicsContext,
                          _ blob: (x: CGFloat, scale: CGFloat, phase: Double,
                                   slot: Int, near: Bool, fruit: Bool)) {
        let grown = PWMotion.growth(index: blob.slot, count: 8, lock: lock)
        guard grown > 0.001 else { return }

        let canopy = blob.near ? PW.treeFront : PW.treeMid
        let highlight = blob.near ? PW.moss : PW.treeFront

        var layer = context
        layer.translateBy(x: blob.x, y: Self.groundY)
        layer.scaleBy(x: blob.scale * grown, y: blob.scale * grown)

        layer.fill(
            Path(roundedRect: CGRect(x: -6, y: -64, width: 12, height: 64), cornerRadius: 5),
            with: .color(PW.trunk))

        // The canopy sways about the top of the trunk; the trunk itself does not.
        var crown = layer
        crown.translateBy(x: 0, y: -60)
        crown.rotate(by: .degrees(PWMotion.sway(at: time, phase: blob.phase) * grown))
        crown.translateBy(x: 0, y: 60)

        for (cx, cy, r) in [(0.0, -92.0, 40.0), (-26.0, -74.0, 25.0), (27.0, -75.0, 24.0)] {
            crown.fill(Self.circle(cx, cy, r), with: .color(canopy))
        }
        for (cx, cy, r) in [(-13.0, -104.0, 9.0), (16.0, -86.0, 6.0)] {
            crown.fill(Self.circle(cx, cy, r), with: .color(highlight))
        }
        if blob.fruit {
            crown.fill(Self.circle(6, -114, 4.5), with: .color(PW.dawnGlow))
        }
    }

    // MARK: Fireflies

    private func drawFly(_ context: inout GraphicsContext,
                         _ fly: (x: CGFloat, y: CGFloat, r: CGFloat, phase: Double, slot: Int)) {
        let grown = PWMotion.growth(index: fly.slot, count: 8, lock: lock)
        let brightness = min(lock, grown) * Self.blink(time: time, phase: fly.phase)
        guard brightness > 0.01 else { return }

        // Two incommensurate sines per axis, so the path meanders instead of looping.
        func position(_ lag: Double) -> CGPoint {
            let t = time - lag
            return CGPoint(
                x: fly.x + 46 * sin(t * 0.55 + fly.phase * 1.7) + 22 * sin(t * 1.31 + fly.phase * 3.1),
                y: fly.y + 30 * sin(t * 0.43 + fly.phase * 2.3) + 16 * sin(t * 1.07 + fly.phase))
        }

        var layer = context
        layer.opacity = brightness

        for (lag, radiusScale, alpha) in [(0.42, 0.50, 0.12), (0.28, 0.62, 0.20), (0.14, 0.78, 0.32)] {
            let point = position(lag)
            layer.fill(Self.circle(point.x, point.y, fly.r * radiusScale),
                       with: .color(PW.dawnGlow.opacity(alpha)))
        }
        let head = position(0)
        layer.fill(Self.circle(head.x, head.y, fly.r * 3.2),
                   with: .color(PW.dawnGlow.opacity(0.16)))
        layer.fill(Self.circle(head.x, head.y, fly.r), with: .color(PW.dawnGlow))
    }

    /// Lit for 22% of a per-fly period, dark the rest — fireflies blink rarely.
    private static func blink(time: Double, phase: Double) -> Double {
        let period = 6.5 + phase.truncatingRemainder(dividingBy: 2.4)
        let cycle = (time / period + phase * 0.37).truncatingRemainder(dividingBy: 1)
        let wrapped = cycle < 0 ? cycle + 1 : cycle
        guard wrapped < 0.22 else { return 0 }
        return sin(wrapped / 0.22 * .pi)
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
}
