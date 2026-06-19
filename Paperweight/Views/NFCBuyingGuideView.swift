import SwiftUI

struct NFCBuyingGuideView: View {
    // ─────────────────────────────────────────────────────────────────────
    // Set your Amazon Associates tag here to monetize the buy links, e.g.
    // "paperweight-20". Leave empty for plain (non-affiliate) links.
    private let amazonAssociatesTag = ""
    // ─────────────────────────────────────────────────────────────────────

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                GlyphOrb(size: 60, systemName: "dot.radiowaves.left.and.right", tint: PW.dawnGlow)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6).padding(.bottom, 16)
                Text("Choosing a token")
                    .font(.spectral(26)).foregroundStyle(PW.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Any cheap NFC tag works. Paperweight reads the chip's built-in ID, so the tag never needs to be programmed — even a blank one is ready out of the pack.")
                    .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8).padding(.horizontal, 6).padding(.bottom, 6)

                SectionHeader(text: "The Short Version").padding(.top, 20).padding(.bottom, 9)
                GroupedCard {
                    infoRow(icon: "checkmark.seal.fill", iconColor: PW.sage,
                            title: "Get an NTAG215 (or 213 / 216)",
                            body: "The most iPhone-compatible chips, a few dollars for a multipack. Memory size doesn't matter here — we only read the ID.")
                }

                SectionHeader(text: "Stickers vs. Hard Tags").padding(.top, 22).padding(.bottom, 9)
                GroupedCard {
                    infoRow(icon: "doc.plaintext", iconColor: PW.sage,
                            title: "Stickers (thin, adhesive)",
                            body: "Cheapest. Sit flat on wood, plastic, or glass. Best stuck somewhere out of the way.")
                    CardDivider()
                    infoRow(icon: "circle.grid.cross", iconColor: PW.sage,
                            title: "Discs, fobs & PVC cards",
                            body: "Tougher and easy to move or hide. Better if you'll tap it daily.")
                }

                SectionHeader(text: "What to Avoid").padding(.top, 22).padding(.bottom, 9)
                GroupedCard {
                    infoRow(icon: "xmark.octagon.fill", iconColor: PW.clay,
                            title: "125 kHz \u{201C}RFID\u{201D} tags",
                            body: "These aren't NFC and iPhone can't read them at all. Skip anything listing \u{201C}125 kHz\u{201D}, \u{201C}EM4100\u{201D}, or \u{201C}proximity card.\u{201D}")
                    CardDivider()
                    infoRow(icon: "rectangle.slash", iconColor: PW.clay,
                            title: "Bare tags on metal",
                            body: "Metal detunes the antenna and the phone won't read it. If it must go on a fridge or lockbox, buy an \u{201C}on-metal\u{201D} / \u{201C}anti-metal\u{201D} tag.")
                    CardDivider()
                    infoRow(icon: "questionmark.circle", iconColor: PW.clay,
                            title: "Unbranded \u{201C}NFC cards\u{201D}",
                            body: "Sometimes MIFARE Classic — usually still readable, but NTAG is the safe bet.")
                }

                SectionHeader(text: "Where to Buy").padding(.top, 22).padding(.bottom, 9)
                GroupedCard {
                    buyRow(title: "NTAG215 tags & multipacks",
                           subtitle: "Amazon", url: amazon("ntag215 nfc tags"))
                    CardDivider()
                    buyRow(title: "NTAG213 NFC stickers",
                           subtitle: "Amazon", url: amazon("ntag213 nfc stickers"))
                    CardDivider()
                    buyRow(title: "On-metal NFC tags",
                           subtitle: "Amazon", url: amazon("on metal nfc tag ntag215"))
                    CardDivider()
                    buyRow(title: "Specialty & bulk (GoToTags)",
                           subtitle: "gototags.com", url: URL(string: "https://gototags.com/nfc/tags/")!)
                }
                Text("Buy links may be affiliate links — they cost you nothing extra and help support Paperweight.")
                    .font(.grotesk(11)).foregroundStyle(PW.textFaint)
                    .padding(.horizontal, 8).padding(.top, 8)

                Text("Put it somewhere a little inconvenient — another room, inside a book, under a shelf. The way out should take a moment of intention.")
                    .font(.spectral(15, italic: true)).foregroundStyle(PW.textMuted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28).padding(.horizontal, 16).padding(.bottom, 28)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .pwScreen()
        .navigationTitle("Buying a Token")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Rows

    private func infoRow(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16)).foregroundStyle(iconColor)
                .frame(width: 20).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.grotesk(14.5, weight: .medium)).foregroundStyle(PW.textPrimary)
                Text(body).font(.grotesk(12.5)).foregroundStyle(PW.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private func buyRow(title: String, subtitle: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.grotesk(14.5)).foregroundStyle(PW.textPrimary)
                    Text(subtitle).font(.grotesk(12)).foregroundStyle(PW.textFaint)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 15)).foregroundStyle(PW.sage)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Affiliate link builder

    private func amazon(_ query: String) -> URL {
        var components = URLComponents(string: "https://www.amazon.com/s")!
        var items = [URLQueryItem(name: "k", value: query)]
        if !amazonAssociatesTag.isEmpty {
            items.append(URLQueryItem(name: "tag", value: amazonAssociatesTag))
        }
        components.queryItems = items
        return components.url!
    }
}
