import SwiftUI

/// Picks the artwork the locked Home draws, showing each style actually running.
///
/// The live preview earns its keep twice: choosing a look from a written
/// description was never a good way to choose a look, and Screen Time doesn't
/// exist in the simulator — so this is the only place the scenes can be seen
/// without a real device and an armed schedule.
struct LockedScenePicker: View {
    @ObservedObject var vm: HomeViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let previewHeight: CGFloat = 168

    /// Stable origin so sway and blink phases don't jump between redraws.
    @State private var epoch = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Style").pwScreenLabel().padding(.top, 6)

                TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                        paused: scenePhase != .active || reduceMotion)) { context in
                    let time = context.date.timeIntervalSince(epoch)
                    VStack(spacing: 14) {
                        ForEach(LockedScene.allCases) { style in
                            card(for: style, time: time)
                        }
                    }
                }

                Text("Shown only while apps are quiet.")
                    .font(.grotesk(13))
                    .foregroundStyle(PW.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollContentBackground(.hidden)
        .pwScreen()
        .navigationTitle("Locked screen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(for style: LockedScene, time: Double) -> some View {
        let selected = vm.config.lockedScene == style
        return Button {
            vm.config.lockedScene = style
            vm.saveConfig()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    PW.black
                    scene(style, time: time)
                }
                .frame(height: Self.previewHeight)
                .clipped()

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(style.title)
                            .font(.grotesk(15))
                            .foregroundStyle(PW.textPrimary)
                        Text(style.blurb)
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
        .accessibilityLabel("\(style.title). \(style.blurb)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Previews always show the scene fully grown — a card that re-sprouted on
    /// every redraw would be noise, not information.
    @ViewBuilder
    private func scene(_ style: LockedScene, time: Double) -> some View {
        switch style {
        case .simple:    SimpleScene(lock: 1)
        case .diorama:   DioramaScene(lock: 1, time: time)
        case .overgrown: OvergrownScene(lock: 1, time: time)
        }
    }
}
