import SwiftUI

// MARK: - GlassOrb

/// The paperweight: a glass dome on the desk, sage light gathered in its base.
/// Same object as the app icon, drawn in SwiftUI so the widget and the
/// glyph screens carry the mark at any size. `dim` mutes the fill and drops
/// the gathered light — used behind lock/key glyphs.
///
/// Geometry in the unit square: the dome's crown is at y 0.08, its base line
/// at 0.58, the front of the base at 0.72, the shadow just under that.
struct GlassOrb: View {
    var size: CGFloat
    var dim: Bool = false

    private var hairline: CGFloat { max(1, size * 0.007) }

    var body: some View {
        ZStack {
            // Contact shadow and the pool of light on the desk.
            Ellipse()
                .fill(dim ? Color.black.opacity(0.4) : PW.sage.opacity(0.3))
                .frame(width: size * 0.92, height: size * 0.18)
                .offset(y: size * 0.25)
                .blur(radius: size * 0.05)

            DomeShape()
                .fill(fill)

            // The far rim of the base, seen through the glass.
            baseRim(opacity: dim ? 0.12 : 0.22)
                .mask(Rectangle().frame(height: size * 0.58).offset(y: -size * 0.21))

            if !dim {
                Ellipse()
                    .fill(RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: PW.dawnGlow.opacity(0.95), location: 0),
                            .init(color: PW.sage.opacity(0.45), location: 0.5),
                            .init(color: PW.sage.opacity(0), location: 1)]),
                        center: .center, startRadius: 0, endRadius: size * 0.26))
                    .frame(width: size * 0.52, height: size * 0.34)
                    .offset(y: size * 0.1)
                    .mask(DomeShape())
            }

            // The front of the base, and the crown's edge.
            baseRim(opacity: dim ? 0.25 : 0.45)
                .mask(Rectangle().frame(height: size * 0.42).offset(y: size * 0.29))
            DomeShape()
                .stroke(LinearGradient(
                    colors: [Color.white.opacity(dim ? 0.35 : 0.8), PW.dawnGlow.opacity(0.15)],
                    startPoint: .top, endPoint: .bottom), lineWidth: hairline)

            // One glint on the crown.
            Ellipse()
                .fill(Color.white.opacity(dim ? 0.15 : 0.55))
                .frame(width: size * 0.26, height: size * 0.14)
                .rotationEffect(.degrees(-28))
                .offset(x: -size * 0.16, y: -size * 0.24)
                .blur(radius: size * 0.012)
        }
        .frame(width: size, height: size)
    }

    private func baseRim(opacity: Double) -> some View {
        Ellipse()
            .stroke(PW.dawnGlow.opacity(opacity), lineWidth: hairline)
            .frame(width: size, height: size * 0.28)
            .offset(y: size * 0.08)
    }

    private var fill: RadialGradient {
        let stops: [Gradient.Stop] = dim
            ? [.init(color: Color(pwHex: 0x8FAE80, alpha: 0.55), location: 0),
               .init(color: Color(pwHex: 0x4A6A42, alpha: 0.5), location: 0.45),
               .init(color: Color(pwHex: 0x0F1A12, alpha: 0.75), location: 1)]
            : [.init(color: Color(pwHex: 0xB7DB98), location: 0),
               .init(color: Color(pwHex: 0x7FAE68), location: 0.28),
               .init(color: Color(pwHex: 0x3C6534), location: 0.62),
               .init(color: Color(pwHex: 0x1B2F1F), location: 0.88),
               .init(color: Color(pwHex: 0x132218), location: 1)]
        return RadialGradient(gradient: Gradient(stops: stops),
                              center: UnitPoint(x: 0.4, y: 0.3),
                              startRadius: 0, endRadius: size * 0.7)
    }
}

/// A hemisphere seen from slightly above: the top half of a circle joined to
/// the front half of its base ellipse. Built from path intersections so no
/// arc-direction guesswork is involved.
struct DomeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cy = rect.minY + h * 0.58
        let r = w / 2
        let circle = Path(ellipseIn: CGRect(x: rect.minX, y: cy - r, width: w, height: 2 * r))
        let base = Path(ellipseIn: CGRect(x: rect.minX, y: cy - h * 0.14, width: w, height: h * 0.28))
        let above = Path(CGRect(x: rect.minX, y: rect.minY - h, width: w, height: cy - rect.minY + h))
        let below = Path(CGRect(x: rect.minX, y: cy, width: w, height: 2 * h))
        return circle.intersection(above).union(base.intersection(below))
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
    /// Defaults to sage — the quiet state. Free windows use moss and the timed
    /// unlock uses clay, matching the accent each state carries elsewhere.
    var tint: Color = PW.sage

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.6), radius: 6)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - NFC scan waves

/// Concentric rings expanding outward behind the dim orb.
struct NFCWaves: View {
    var size: CGFloat
    /// Defaults to sage, matching the original scan prompt. The unlock screen
    /// is an all-clay exit, so it passes `PW.clay` instead — no new ripple
    /// drawing code, just a tint the caller controls.
    var tint: Color = PW.sage
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            wave(delay: 0)
            wave(delay: 1.3)
        }
        .frame(width: size, height: size)
        // Reduce Motion: never flip `animate`, so the rings render once at
        // their resting scale/opacity and stay put — same pattern as the
        // perpetual timelines in HomeView/QuietThemePicker.
        .onAppear { if !reduceMotion { animate = true } }
    }

    private func wave(delay: Double) -> some View {
        Circle()
            .stroke(tint.opacity(0.5), lineWidth: 1.5)
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
                    .font(.system(size: size * 0.36, weight: .regular))
                    .foregroundStyle(tint)
                    .offset(y: -size * 0.06)
            )
    }
}
