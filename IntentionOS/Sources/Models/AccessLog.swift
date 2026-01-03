import Foundation

enum AccessType: String, Codable {
    case app
    case url
}

enum AllowedReason: String, Codable {
    case explicit // Explicitly added to intention
    case bundle // From a bundle attached to intention
    case config // From config file rules
    case learned // From learned rules
    case llm // LLM approved
    case override // User typed break-glass phrase
    case alwaysAllowed = "always_allowed" // System always-allowed list
}

struct AccessLogEntry: Identifiable, Codable {
    let id: Int64
    let intentionId: Int64
    let timestamp: Date
    let type: AccessType
    let identifier: String
    let wasAllowed: Bool
    let allowedReason: AllowedReason?
    let wasOverride: Bool
    let addedToLearned: Bool
}

struct LearnedRule: Identifiable, Codable {
    let id: Int64
    let intentionPattern: String
    let type: AccessType
    let identifier: String
    let allowed: Bool
    let createdAt: Date
}
