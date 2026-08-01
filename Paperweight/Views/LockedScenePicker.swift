import SwiftUI

/// Picks the artwork the locked Home draws. Cosmetic only — nothing here changes
/// what is restricted, which is why it is editable even while Paperweight is on.
struct LockedScenePicker: View {
    @ObservedObject var vm: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Style").pwScreenLabel()
                    .padding(.top, 6).padding(.bottom, 10)

                GroupedCard {
                    ForEach(Array(LockedScene.allCases.enumerated()), id: \.element.id) { index, scene in
                        if index > 0 { CardDivider() }
                        Button {
                            vm.config.lockedScene = scene
                            vm.saveConfig()
                        } label: {
                            row(for: scene)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Shown only while apps are quiet.")
                    .font(.grotesk(13))
                    .foregroundStyle(PW.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollContentBackground(.hidden)
        .pwScreen()
        .navigationTitle("Locked screen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for scene: LockedScene) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(scene.title)
                    .font(.grotesk(15))
                    .foregroundStyle(PW.textPrimary)
                Text(scene.blurb)
                    .font(.grotesk(13))
                    .foregroundStyle(PW.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if vm.config.lockedScene == scene {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PW.sage)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
