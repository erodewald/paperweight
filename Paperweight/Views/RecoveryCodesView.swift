import SwiftUI

struct RecoveryCodesView: View {
    let codes: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var copiedAll = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    GlyphOrb(size: 46, systemName: "key.viewfinder", tint: PW.dawnGlow)
                        .padding(.top, 14).padding(.bottom, 14)

                    Text("Save your codes")
                        .font(.spectral(24)).foregroundStyle(PW.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Each works once. Keep them somewhere you can reach without your phone.")
                        .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8).padding(.horizontal, 20).padding(.bottom, 24)

                    VStack(spacing: 8) {
                        ForEach(codes, id: \.self) { code in
                            Text(displayFormat(code))
                                .font(.grotesk(15, weight: .semibold))
                                .tracking(2)
                                .foregroundStyle(PW.textPrimary)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(PW.surfaceRaised)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        }
                    }

                    Button { copyAll() } label: {
                        HStack(spacing: 9) {
                            Image(systemName: copiedAll ? "checkmark" : "doc.on.doc").font(.system(size: 14))
                            Text(copiedAll ? "Copied!" : "Copy all codes").font(.grotesk(14, weight: .semibold))
                        }
                        .foregroundStyle(PW.dawnGlow)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(PW.deepForest)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PW.sage.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .animation(.default, value: copiedAll)
                    .padding(.top, 20)

                    Text("These codes will not be shown again.")
                        .font(.grotesk(13)).foregroundStyle(PW.warn)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(PW.surfaceRaised.ignoresSafeArea())
            .navigationTitle("Recovery Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(PW.sage)
                }
            }
        }
    }

    /// Presentation-only reformatting: strips whatever separator the raw code
    /// already carries and re-splits it around the midpoint for display. Does
    /// not touch generation, storage, or comparison — `RecoveryCodeService`
    /// normalizes separators away before hashing, so this is purely cosmetic.
    /// If a code's length can't split evenly, the first half absorbs the odd
    /// character rather than crashing.
    private func displayFormat(_ code: String) -> String {
        let compact = code.replacingOccurrences(of: "-", with: "")
        guard compact.count > 1 else { return compact }
        let mid = compact.index(compact.startIndex, offsetBy: (compact.count + 1) / 2)
        return "\(compact[..<mid]) · \(compact[mid...])"
    }

    private func copyAll() {
        UIPasteboard.general.string = codes.joined(separator: "\n")
        copiedAll = true
    }
}
