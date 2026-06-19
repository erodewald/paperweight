import SwiftUI
import UniformTypeIdentifiers

/// A plain-text document for exporting the codes to the Files app.
private struct TextFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct RecoveryCodesView: View {
    let codes: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var copiedCode: String?
    @State private var copiedAll = false
    @State private var showingExporter = false

    /// Formatted block for the share sheet — 1Password, Notes, etc. receive this
    /// as a saveable secure note.
    private var shareText: String {
        let body = codes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return """
        Paperweight recovery codes
        Each works once. Use one to turn off Paperweight if you lose your NFC token.

        \(body)
        """
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    GlyphOrb(size: 64, systemName: "key.fill", tint: PW.dawnGlow)
                        .padding(.top, 14).padding(.bottom, 14)

                    Text("Save your codes")
                        .font(.spectral(24)).foregroundStyle(PW.textPrimary)
                    Text("Each works once. Tap a code to copy it, or save them all to your password manager.")
                        .font(.grotesk(12.5)).foregroundStyle(PW.textMuted)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8).padding(.horizontal, 20).padding(.bottom, 20)

                    VStack(spacing: 8) {
                        ForEach(codes, id: \.self) { code in
                            Button { copy(code) } label: {
                                Text(code)
                                    .font(.grotesk(15, weight: .semibold))
                                    .tracking(0.14 * 15)
                                    .foregroundStyle(PW.textPrimary)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(PW.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PW.hairline, lineWidth: 1))
                                    .overlay(alignment: .trailing) {
                                        Image(systemName: copiedCode == code ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 13))
                                            .foregroundStyle(copiedCode == code ? PW.sage : PW.textFaint)
                                            .padding(.trailing, 14)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ShareLink(item: shareText) {
                        HStack(spacing: 9) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                            Text("Save to a password manager").font(.grotesk(14))
                        }
                        .foregroundStyle(PW.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(PW.sage)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: PW.sage.opacity(0.28), radius: 14)
                    }
                    .padding(.top, 20)

                    HStack(spacing: 10) {
                        Button { copyAll() } label: {
                            outlineLabel(systemName: copiedAll ? "checkmark" : "doc.on.doc",
                                         title: copiedAll ? "Copied!" : "Copy all")
                        }
                        .buttonStyle(.plain)
                        .animation(.default, value: copiedAll)

                        Button { showingExporter = true } label: {
                            outlineLabel(systemName: "folder", title: "Save to Files")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 10)

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
            .fileExporter(isPresented: $showingExporter,
                          document: TextFile(text: shareText),
                          contentType: .plainText,
                          defaultFilename: "Paperweight Recovery Codes") { _ in }
        }
    }

    private func outlineLabel(systemName: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName).font(.system(size: 14))
            Text(title).font(.grotesk(14))
        }
        .foregroundStyle(PW.sage)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(PW.sage.opacity(0.3), lineWidth: 1))
    }

    private func copy(_ code: String) {
        UIPasteboard.general.string = code
        withAnimation { copiedCode = code }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copiedCode == code { withAnimation { copiedCode = nil } }
        }
    }

    private func copyAll() {
        UIPasteboard.general.string = codes.joined(separator: "\n")
        copiedAll = true
    }
}
