import FamilyControls

extension FamilyActivitySelection {
    var summary: String {
        let appCount = applicationTokens.count
        let catCount = categoryTokens.count
        let domainCount = webDomainTokens.count

        var parts: [String] = []
        if appCount > 0 { parts.append(String(localized: "\(appCount) apps", bundle: L10n.bundle, comment: "How many apps are chosen; has a plural rule")) }
        if catCount > 0 { parts.append(String(localized: "\(catCount) categories", bundle: L10n.bundle, comment: "How many app categories are chosen; has a plural rule")) }
        if domainCount > 0 { parts.append(String(localized: "\(domainCount) domains", bundle: L10n.bundle, comment: "How many web domains are chosen; has a plural rule")) }
        return parts.joined(separator: String(localized: ", ", bundle: L10n.bundle, comment: "List separator"))
    }

    var isEmpty: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }
}
