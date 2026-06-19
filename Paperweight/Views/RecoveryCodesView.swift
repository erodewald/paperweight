import SwiftUI

struct RecoveryCodesView: View {
    let codes: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text("Save Your Recovery Codes")
                            .font(.title2.bold())
                        Text("Each code works once. Keep them somewhere you can reach without your phone — a printed note, a trusted person, a password manager on another device.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.top)

                    VStack(spacing: 8) {
                        ForEach(codes, id: \.self) { code in
                            Text(code)
                                .font(.system(.body, design: .monospaced).bold())
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal)

                    Button {
                        UIPasteboard.general.string = codes.joined(separator: "\n")
                        copied = true
                    } label: {
                        Label(copied ? "Copied!" : "Copy All Codes", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                    .animation(.default, value: copied)

                    Text("These codes will not be shown again.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                .padding(.bottom)
            }
            .navigationTitle("Recovery Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
