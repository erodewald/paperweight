import SwiftUI

/// Text that disintegrates into drifting particles — a "Thanos snap" — when
/// `dissolve` flips to true. The original glyphs fade as a particle cloud over
/// their bounds scatters up-and-out, staggered left-to-right.
struct DissolveText: View {
    let text: String
    var dissolve: Bool
    var font: Font = .grotesk(20, weight: .semibold)
    var tracking: CGFloat = 2.8
    var color: Color = PW.textPrimary

    var body: some View {
        Text(text)
            .font(font)
            .tracking(tracking)
            .foregroundStyle(color)
            .opacity(dissolve ? 0 : 1)
            .blur(radius: dissolve ? 1.5 : 0)
            .animation(.easeOut(duration: 0.6), value: dissolve)
            .overlay {
                GeometryReader { geo in
                    if dissolve {
                        ParticleField(size: geo.size, color: color)
                    }
                }
            }
    }
}

private struct ParticleField: View {
    let size: CGSize
    let color: Color
    @State private var scattered = false
    private let particles: [Particle]

    init(size: CGSize, color: Color) {
        self.size = size
        self.color = color
        var grid: [Particle] = []
        let spacing: CGFloat = 5
        let cols = max(1, Int(size.width / spacing))
        let rows = max(1, Int(size.height / spacing))
        for r in 0..<rows {
            for c in 0..<cols {
                let x = (CGFloat(c) + 0.5) * spacing
                let y = (CGFloat(r) + 0.5) * spacing
                let frac = size.width > 0 ? x / size.width : 0
                grid.append(Particle(
                    x: x, y: y,
                    side: CGFloat.random(in: 1.2...2.8),
                    dx: CGFloat.random(in: 4...18) + frac * 16,
                    dy: CGFloat.random(in: -38 ... -8),
                    delay: Double(frac) * 0.45 + Double.random(in: 0...0.08)))
            }
        }
        particles = grid
    }

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Rectangle()
                    .fill(color)
                    .frame(width: p.side, height: p.side)
                    .position(x: p.x, y: p.y)
                    .offset(x: scattered ? p.dx : 0, y: scattered ? p.dy : 0)
                    .opacity(scattered ? 0 : 0.85)
                    .animation(.easeOut(duration: 0.9).delay(p.delay), value: scattered)
            }
        }
        .allowsHitTesting(false)
        .onAppear { scattered = true }
    }

    struct Particle: Identifiable {
        let id = UUID()
        let x, y, side, dx, dy: CGFloat
        let delay: Double
    }
}
