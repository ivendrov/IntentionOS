import Foundation

struct FilterResult {
    let allowed: Bool
    let reason: AllowedReason?
    let message: String?

    static func allow(reason: AllowedReason, message: String? = nil) -> FilterResult {
        FilterResult(allowed: true, reason: reason, message: message)
    }

    static func block(message: String? = nil) -> FilterResult {
        FilterResult(allowed: false, reason: nil, message: message)
    }
}
