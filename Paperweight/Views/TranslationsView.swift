import SwiftUI

/// Settings → Language & translations. Shows the language the app is running
/// in, says plainly when that language's translations are machine-made and
/// unreviewed, and offers two ways to help: report a wrong translation, or ask
/// for a language. Both open a prefilled GitHub issue form in the browser; the
/// app itself talks to no server.
struct TranslationsView: View {
    @Environment(\.openURL) private var openURL

    private let context = TranslationFeedback.Context.current()
    private let status = TranslationStatus.load()

    private var languageName: String { TranslationFeedback.languageName(context.appLanguage) }
    private var unreviewed: Bool { status?.needsReview(context.appLanguage) ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("This app", comment: "Section heading over the current-language row").pwScreenLabel()
                    .padding(.top, 6).padding(.bottom, 10)
                GroupedCard {
                    HStack {
                        Text("Language", comment: "Row label: the language the app is running in")
                            .font(.grotesk(15)).foregroundStyle(PW.textPrimary)
                        Spacer(minLength: 12)
                        Text(languageName).font(.grotesk(13)).foregroundStyle(PW.textMuted)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    if unreviewed {
                        CardDivider()
                        Text("This \(languageName) translation was made by a machine and hasn't been checked by a \(languageName) speaker yet. If something reads wrong, say so.",
                             comment: "Notice under the language row; both placeholders are the language name")
                            .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    CardDivider()
                    Button { openURL(URL(string: UIApplication.openSettingsURLString)!) } label: {
                        NavRow(title: "Change language", systemImage: "globe", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }

                Text("Help", comment: "Section heading over the two feedback links").pwScreenLabel()
                    .padding(.top, 22).padding(.bottom, 10)
                GroupedCard {
                    Link(destination: TranslationFeedback.reportURL(context)) {
                        NavRow(title: "Report a wrong translation", systemImage: "text.badge.xmark", showsChevron: true)
                    }
                    CardDivider()
                    Link(destination: TranslationFeedback.requestURL(context)) {
                        NavRow(title: "Request a language", systemImage: "plus.bubble", showsChevron: true)
                    }
                }
                Text("Both open a form on GitHub with the language and version filled in. Nothing is sent until you post it.")
                    .font(.grotesk(13)).foregroundStyle(PW.textFaint)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .scrollContentBackground(.hidden)
        .pwScreen()
        .navigationTitle("Language & translations")
        .navigationBarTitleDisplayMode(.inline)
    }
}
