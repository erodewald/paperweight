import SwiftUI

/// Picks the artwork the quiet screen draws, showing each theme actually running.
///
/// The live preview earns its keep twice: choosing a look from a written
/// description was never a good way to choose a look, and Screen Time doesn't
/// exist in the simulator — so this is the only place these can be seen without
/// a real device and an armed schedule.
struct QuietThemePicker: View {
    @ObservedObject var vm: HomeViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let previewHeight: CGFloat = 168

    /// Stable origin so sway and blink phases don't jump between redraws.
    @State private var epoch = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Changes only what you see while apps are quiet. It never changes what's blocked.")
                    .font(.grotesk(13))
                    .foregroundStyle(PW.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                        paused: scenePhase != .active || reduceMotion)) { context in
                    let time = context.date.timeIntervalSince(epoch)
                    VStack(spacing: 14) {
                        ForEach(QuietTheme.allCases) { theme in
                            card(for: theme, time: time)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollContentBackground(.hidden)
        .pwScreen()
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(for theme: QuietTheme, time: Double) -> some View {
        let selected = vm.config.quietTheme == theme
        return Button {
            vm.config.quietTheme = theme
            vm.saveConfig()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Simple draws nothing, so it gets a row rather than a preview
                // box full of black, which read as a failed render.
                if theme.hasArtwork {
                    ZStack {
                        PW.black
                        scene(theme, time: time)
                    }
                    .frame(height: Self.previewHeight)
                    .clipped()
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(theme.title)
                            .font(.grotesk(15))
                            .foregroundStyle(PW.textPrimary)
                        Text(theme.blurb)
                            .font(.grotesk(13))
                            .foregroundStyle(PW.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? PW.sage : PW.textFaint)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(PW.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? PW.sage.opacity(0.5) : PW.hairline,
                            lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title). \(theme.blurb)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Previews always show the artwork fully grown — a card that re-sprouted on
    /// every redraw would be noise, not information.
    @ViewBuilder
    private func scene(_ theme: QuietTheme, time: Double) -> some View {
        switch theme {
        case .simple:    EmptyView()
        case .diorama:   DioramaScene(lock: 1, time: time)
        case .overgrown: OvergrownScene(lock: 1, time: time)
        }
    }
}
