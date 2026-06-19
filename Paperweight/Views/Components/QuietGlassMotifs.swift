import SwiftUI

// MARK: - GlassOrb

/// The paperweight: a glass sphere with a suspended leaf and a specular glint.
/// `dim` drops the leaf and mutes the fill — used behind lock/key glyphs.
struct GlassOrb: View {
    var size: CGFloat
    var dim: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .overlay(
                    Circle().stroke(PW.dawnGlow.opacity(dim ? 0.22 : 0.32),
                                    lineWidth: max(1, size * 0.007))
                )

            if !dim {
                LeafShape()
                    .fill(LinearGradient(colors: [PW.sage, PW.moss],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: size, height: size)
                LeafSpine()
                    .stroke(Color(pwHex: 0x2E4A30), lineWidth: max(1, size * 0.012))
                    .frame(width: size, height: size)
            }

            Ellipse()
                .fill(Color.white.opacity(dim ? 0.18 : 0.5))
                .frame(width: size * 0.28, height: size * 0.16)
                .rotationEffect(.degrees(-28))
                .offset(x: -size * 0.18, y: -size * 0.20)
                .blur(radius: size * 0.01)
        }
        .frame(width: size, height: size)
    }

    private var fill: RadialGradient {
        let stops: [Gradient.Stop] = dim
            ? [.init(color: Color(pwHex: 0xB4C4AA, alpha: 0.5), location: 0),
               .init(color: Color(pwHex: 0x5E8C4F, alpha: 0.22), location: 0.4),
               .init(color: Color(pwHex: 0x080E09, alpha: 0.6), location: 1)]
            : [.init(color: Color(pwHex: 0xECF8D4, alpha: 0.97), location: 0),
               .init(color: Color(pwHex: 0x9DC47B, alpha: 0.5), location: 0.3),
               .init(color: Color(pwHex: 0x2E4A30, alpha: 0.58), location: 0.68),
               .init(color: Color(pwHex: 0x0A140C, alpha: 0.7), location: 1)]
        return RadialGradient(gradient: Gradient(stops: stops),
                              center: UnitPoint(x: 0.38, y: 0.30),
                              startRadius: 0, endRadius: size * 0.62)
    }
}

/// Leaf outline in unit space, scaled to the orb frame.
private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        var path = Path()
        path.move(to: p(0.5, 0.28))
        path.addCurve(to: p(0.5, 0.74), control1: p(0.62, 0.36), control2: p(0.62, 0.62))
        path.addCurve(to: p(0.5, 0.28), control1: p(0.38, 0.62), control2: p(0.38, 0.36))
        path.closeSubpath()
        return path
    }
}

private struct LeafSpine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.32))
        path.addLine(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.70))
        return path
    }
}

// MARK: - Soft glow

/// A soft radial halo behind the orb. Optional slow pulse.
struct OrbGlow: View {
    var size: CGFloat
    var pulse: Bool = true
    @State private var on = false

    var body: some View {
        Circle()
            .fill(RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: PW.moss.opacity(0.2), location: 0),
                    .init(color: .clear, location: 0.68)]),
                center: .center, startRadius: 0, endRadius: size * 0.5))
            .frame(width: size, height: size)
            .blur(radius: 6)
            .opacity(pulse ? (on ? 0.92 : 0.55) : 0.7)
            .scaleEffect(pulse && on ? 1.04 : 1.0)
            .animation(pulse ? .easeInOut(duration: 8).repeatForever(autoreverses: true) : nil, value: on)
            .onAppear { if pulse { on = true } }
    }
}

// MARK: - ProgressRing

/// Thin ring tracking time remaining in the current quiet window.
struct ProgressRing: View {
    var progress: Double          // 0…1
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(PW.sage, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: PW.sage.opacity(0.6), radius: 6)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - NFC scan waves

/// Concentric rings expanding outward behind the dim orb.
struct NFCWaves: View {
    var size: CGFloat
    @State private var animate = false

    var body: some View {
        ZStack {
            wave(delay: 0)
            wave(delay: 1.3)
        }
        .frame(width: size, height: size)
        .onAppear { animate = true }
    }

    private func wave(delay: Double) -> some View {
        Circle()
            .stroke(PW.sage.opacity(0.5), lineWidth: 1.5)
            .frame(width: size, height: size)
            .scaleEffect(animate ? 1.9 : 0.6)
            .opacity(animate ? 0 : 0.7)
            .animation(.easeOut(duration: 2.6).repeatForever(autoreverses: false).delay(delay),
                       value: animate)
    }
}

/// A dim orb with an SF Symbol glyph centered on it (lock, key, broken lock…).
struct GlyphOrb: View {
    var size: CGFloat
    var systemName: String
    var tint: Color = PW.dawnGlow

    var body: some View {
        GlassOrb(size: size, dim: true)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.38, weight: .regular))
                    .foregroundStyle(tint)
            )
    }
}
