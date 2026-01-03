import Foundation

struct AppConfig: Codable {
    var defaultDurationMinutes: Int = 25
    var warningBeforeEndMinutes: Int = 5
    var unlimitedCheckinMinutes: Int = 30
    var breakGlassPhrase: String = "I am choosing distraction"
    var reassertFocusDelayMs: Int = 100
    var llmProvider: String = "openai"
    var llmModel: String = "gpt-4o-mini"
    var llmApiKeyEnv: String = "OPENAI_API_KEY"
    var theme: String = "dark"
    var backgroundAnimation: String = "orb"

    static let `default` = AppConfig()
}

struct RulesConfig: Codable {
    var alwaysAllowed: AllowBlockList = AllowBlockList()
    var alwaysBlocked: AllowBlockList = AllowBlockList()
    var intentionRules: [IntentionRule] = []

    static let `default` = RulesConfig()
}

struct AllowBlockList: Codable {
    var apps: [String] = []
    var urls: [String] = []
}

struct IntentionRule: Codable {
    var pattern: String = ""
    var allowApps: [String] = []
    var allowUrls: [String] = []

    enum CodingKeys: String, CodingKey {
        case pattern
        case allowApps = "allow_apps"
        case allowUrls = "allow_urls"
    }
}

struct BundleConfig: Codable {
    var bundles: [BundleEntry] = []

    static let `default` = BundleConfig()
}

struct BundleEntry: Codable {
    var name: String
    var apps: [BundleAppEntry] = []
    var urls: [String] = []
}

struct BundleAppEntry: Codable {
    var id: String
    var name: String
}
