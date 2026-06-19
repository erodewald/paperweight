import SwiftUI

struct RecoveryCodesView: View {
    let codes: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    GlyphOrb(size: 64, systemName: "key.fill", tint: PW.dawnGlow)
                        .padding(.top, 14).padding(.bottom, 14)

                    Text("Save your codes")
                        .font(.spectral(24)).foregroundStyle(PW.textPrimary)
                    Text("Each works once. Keep them somewhere you can reach without your phone.")
                        .font(.grotesk(12.5)).foregroundStyle(PW.textMuted)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8).padding(.horizontal, 20).padding(.bottom, 20)

                    VStack(spacing: 8) {
                        ForEach(codes, id: \.self) { code in
                            Text(code)
                                .font(.grotesk(15, weight: .semibold))
                                .tracking(0.14 * 15)
                                .foregroundStyle(PW.textPrimary)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(PW.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(PW.hairline, lineWidth: 1))
                        }
                    }

                    Button {
                        UIPasteboard.general.string = codes.joined(separator: "\n")
                        copied = true
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 14))
                            Text(copied ? "Copied!" : "Copy all codes").font(.grotesk(14))
                        }
                        .foregroundStyle(PW.sage)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(PW.sage.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    .animation(.default, value: copied)

                    Text("These codes will not be shown again.")
                        .font(.grotesk(12)).foregroundStyle(PW.warn)
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
}
