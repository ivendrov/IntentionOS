import Foundation

class RuleEngine {
    static let shared = RuleEngine()

    private init() {}

    // MARK: - App Checking

    func checkApp(bundleId: String, appName: String, intention: Intention) -> FilterResult {
        let config = ConfigManager.shared

        // 1. Check always-allowed apps (config)
        if config.rulesConfig.alwaysAllowed.apps.contains(bundleId) {
            return .allow(reason: .alwaysAllowed)
        }

        // 2. Check always-blocked apps (config)
        if config.rulesConfig.alwaysBlocked.apps.contains(bundleId) {
            return .block(message: "App is on the always-blocked list")
        }

        // 3. Check if any selected bundle has allowAllApps = true
        if hasAllowAllAppsBundle(intentionId: intention.id) {
            return .allow(reason: .bundle, message: "Admin bundle allows all apps")
        }

        // 4. Check explicit intention apps list
        let intentionApps = DatabaseManager.shared.getIntentionApps(intentionId: intention.id)
        if intentionApps.contains(where: { $0.bundleId == bundleId }) {
            let app = intentionApps.first { $0.bundleId == bundleId }!
            let reason: AllowedReason = app.fromBundleId != nil ? .bundle : .explicit
            return .allow(reason: reason)
        }

        // 5. If strict mode (LLM filtering disabled), block everything else
        if !intention.llmFilteringEnabled {
            return .block(message: "Strict mode: only explicitly allowed apps are permitted")
        }

        // 6. Check config intention rules (pattern matching)
        for rule in config.rulesConfig.intentionRules {
            if matchesPattern(intention.text, pattern: rule.pattern) {
                if rule.allowApps.contains(bundleId) {
                    return .allow(reason: .config)
                }
            }
        }

        // 7. Check learned rules
        if let learnedRule = DatabaseManager.shared.findLearnedRule(type: .app, identifier: bundleId) {
            if learnedRule.allowed {
                return .allow(reason: .learned)
            } else {
                return .block(message: "Previously marked as distraction")
            }
        }

        // 8. For Phase 1, we don't have LLM integration yet, so block unknown apps
        // In Phase 2, this would call the LLM
        return .block(message: "App not recognized for this intention")
    }

    /// Check if any bundle selected for this intention has allowAllApps = true
    private func hasAllowAllAppsBundle(intentionId: Int64) -> Bool {
        let selectedBundleIds = DatabaseManager.shared.getIntentionBundleIds(intentionId: intentionId)
        let allBundles = DatabaseManager.shared.getAllBundles()

        for bundle in allBundles {
            if selectedBundleIds.contains(bundle.id) && bundle.allowAllApps {
                return true
            }
        }
        return false
    }

    /// Check if any bundle selected for this intention has allowAllURLs = true
    private func hasAllowAllURLsBundle(intentionId: Int64) -> Bool {
        let selectedBundleIds = DatabaseManager.shared.getIntentionBundleIds(intentionId: intentionId)
        let allBundles = DatabaseManager.shared.getAllBundles()

        for bundle in allBundles {
            if selectedBundleIds.contains(bundle.id) && bundle.allowAllURLs {
                return true
            }
        }
        return false
    }

    // MARK: - URL Checking

    func checkURL(url: String, intention: Intention) -> FilterResult {
        let config = ConfigManager.shared
        let normalizedURL = normalizeURL(url)

        // 1. Check always-allowed URLs (config) - substring match
        for pattern in config.rulesConfig.alwaysAllowed.urls {
            let normalizedPattern = normalizeURL(pattern)
            if normalizedURL.contains(normalizedPattern) || url.contains(pattern) {
                return .allow(reason: .alwaysAllowed)
            }
        }

        // 2. Check always-blocked URLs (config) - substring match
        for pattern in config.rulesConfig.alwaysBlocked.urls {
            let normalizedPattern = normalizeURL(pattern)
            if normalizedURL.contains(normalizedPattern) || url.contains(pattern) {
                return .block(message: "URL is on the always-blocked list")
            }
        }

        // 3. Check if any selected bundle has allowAllURLs = true
        if hasAllowAllURLsBundle(intentionId: intention.id) {
            return .allow(reason: .bundle, message: "Admin bundle allows all URLs")
        }

        // 4. Check explicit intention URLs list (simple substring match)
        let intentionURLs = DatabaseManager.shared.getIntentionURLs(intentionId: intention.id)
        for intentionURL in intentionURLs {
            // Simple substring match: if the URL contains the pattern anywhere, allow it
            let normalizedPattern = normalizeURL(intentionURL.pattern)
            if normalizedURL.contains(normalizedPattern) || url.contains(intentionURL.pattern) {
                let reason: AllowedReason = intentionURL.fromBundleId != nil ? .bundle : .explicit
                return .allow(reason: reason)
            }
        }

        // 5. If strict mode, block everything else
        if !intention.llmFilteringEnabled {
            return .block(message: "Strict mode: only explicitly allowed URLs are permitted")
        }

        // 6. Check config intention rules (simple substring match)
        for rule in config.rulesConfig.intentionRules {
            if matchesPattern(intention.text, pattern: rule.pattern) {
                for urlPattern in rule.allowUrls {
                    let normalizedPattern = normalizeURL(urlPattern)
                    if normalizedURL.contains(normalizedPattern) || url.contains(urlPattern) {
                        return .allow(reason: .config)
                    }
                }
            }
        }

        // 7. Check learned rules
        // For URLs, we check if the domain/path pattern was learned
        if let learnedRule = DatabaseManager.shared.findLearnedRule(type: .url, identifier: extractDomain(from: normalizedURL)) {
            if learnedRule.allowed {
                return .allow(reason: .learned)
            } else {
                return .block(message: "Previously marked as distraction")
            }
        }

        // 8. Block unknown URLs (LLM would be called in Phase 2)
        return .block(message: "URL not recognized for this intention")
    }

    // MARK: - Pattern Matching

    /// Matches intention text against a regex-like pattern from config
    private func matchesPattern(_ text: String, pattern: String) -> Bool {
        // Pattern is a pipe-separated list of keywords
        let keywords = pattern.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let lowercaseText = text.lowercased()

        return keywords.contains { keyword in
            lowercaseText.contains(keyword)
        }
    }

    /// Matches URL against a glob pattern
    /// Supports * as wildcard
    func matchesGlob(_ url: String, pattern: String) -> Bool {
        // Convert glob pattern to regex
        var regexPattern = NSRegularExpression.escapedPattern(for: pattern)
        regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")

        // Make it match the full string
        regexPattern = "^" + regexPattern + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) else {
            return false
        }

        let range = NSRange(url.startIndex..., in: url)
        return regex.firstMatch(in: url, options: [], range: range) != nil
    }

    // MARK: - URL Helpers

    private func normalizeURL(_ url: String) -> String {
        var normalized = url

        // Remove protocol
        if normalized.hasPrefix("https://") {
            normalized = String(normalized.dropFirst(8))
        } else if normalized.hasPrefix("http://") {
            normalized = String(normalized.dropFirst(7))
        }

        // Remove www.
        if normalized.hasPrefix("www.") {
            normalized = String(normalized.dropFirst(4))
        }

        return normalized
    }

    private func extractDomain(from url: String) -> String {
        let normalized = normalizeURL(url)
        if let slashIndex = normalized.firstIndex(of: "/") {
            return String(normalized[..<slashIndex])
        }
        return normalized
    }
}
