import Foundation

/// A buy link. Either an Amazon `query` (the affiliate tag is appended) or a
/// direct `url`. `url` wins if both are present.
struct RemoteBuyLink: Codable, Identifiable, Hashable {
    var id: String { title }
    var title: String
    var subtitle: String
    var query: String?
    var url: String?
}

/// Remotely-tunable settings. Everything is optional so a partial JSON still
/// decodes and missing fields keep their bundled defaults.
struct RemoteConfig: Codable {
    var amazonAssociatesTag: String?
    var buyLinks: [RemoteBuyLink]?

    static let bundled = RemoteConfig(
        amazonAssociatesTag: nil,
        buyLinks: [
            .init(title: "NTAG215 tags & multipacks", subtitle: "Amazon", query: "ntag215 nfc tags", url: nil),
            .init(title: "NTAG213 NFC stickers", subtitle: "Amazon", query: "ntag213 nfc stickers", url: nil),
            .init(title: "On-metal NFC tags", subtitle: "Amazon", query: "on metal nfc tag ntag215", url: nil),
            .init(title: "Specialty & bulk (GoToTags)", subtitle: "gototags.com", query: nil,
                  url: "https://gototags.com/nfc/tags/")
        ])
}

/// Fetches `RemoteConfig` from a hosted JSON, caches it, and falls back to the
/// bundled defaults. Lets the affiliate tag / buy links change without a new
/// build.
///
/// To enable: host a JSON like
/// ```
/// { "amazonAssociatesTag": "paperweight-20",
///   "buyLinks": [ { "title": "...", "subtitle": "Amazon", "query": "ntag215 nfc tags" },
///                 { "title": "...", "subtitle": "vendor.com", "url": "https://..." } ] }
/// ```
/// (e.g. a GitHub Pages file, gist raw URL, or S3 object) and set `configURL`.
@MainActor
final class RemoteConfigService: ObservableObject {
    static let shared = RemoteConfigService()

    // ← Set to your hosted JSON to enable remote updates. nil = bundled only.
    private let configURL: URL? = nil

    private let cacheKey = "remoteConfig.v1"
    private let store = UserDefaults(suiteName: Paperweight.appGroupID) ?? .standard

    @Published private(set) var current: RemoteConfig

    private init() {
        if let data = store.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(RemoteConfig.self, from: data) {
            current = cached
        } else {
            current = .bundled
        }
    }

    /// Fetches the latest config; silently keeps the cached/bundled value on any
    /// failure (offline, bad JSON, no URL set).
    func refresh() async {
        guard let configURL else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: configURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let config = try? JSONDecoder().decode(RemoteConfig.self, from: data) else { return }
            current = config
            store.set(data, forKey: cacheKey)
        } catch {
            // keep cached/bundled
        }
    }

    /// Resolves a link to a tappable URL, appending the affiliate tag to Amazon
    /// searches.
    func url(for link: RemoteBuyLink) -> URL? {
        if let direct = link.url, let url = URL(string: direct) { return url }
        if let query = link.query { return amazonURL(query: query) }
        return nil
    }

    private func amazonURL(query: String) -> URL? {
        var components = URLComponents(string: "https://www.amazon.com/s")
        var items = [URLQueryItem(name: "k", value: query)]
        if let tag = current.amazonAssociatesTag, !tag.isEmpty {
            items.append(URLQueryItem(name: "tag", value: tag))
        }
        components?.queryItems = items
        return components?.url
    }
}
