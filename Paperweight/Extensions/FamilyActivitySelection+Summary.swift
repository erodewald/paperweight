import FamilyControls

extension FamilyActivitySelection {
    var summary: String {
        let appCount = applicationTokens.count
        let catCount = categoryTokens.count
        let domainCount = webDomainTokens.count

        var parts: [String] = []
        if appCount > 0 { parts.append("\(appCount) app\(appCount == 1 ? "" : "s")") }
        if catCount > 0 { parts.append("\(catCount) categor\(catCount == 1 ? "y" : "ies")") }
        if domainCount > 0 { parts.append("\(domainCount) domain\(domainCount == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    var isEmpty: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }
}
