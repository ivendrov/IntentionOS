import Foundation

struct Intention: Identifiable, Codable {
    let id: Int64
    var text: String
    var durationSeconds: Int? // nil = unlimited (30-min check-ins)
    var startedAt: Date
    var endedAt: Date?
    var endReason: EndReason?
    var llmFilteringEnabled: Bool

    enum EndReason: String, Codable {
        case completed
        case newIntention = "new_intention"
        case choseDistraction = "chose_distraction"
        case checkinContinue = "checkin_continue"
    }

    var isActive: Bool {
        endedAt == nil
    }

    var remainingSeconds: Int? {
        guard let duration = durationSeconds else { return nil }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        return max(0, duration - elapsed)
    }

    var isExpired: Bool {
        guard let remaining = remainingSeconds else { return false }
        return remaining <= 0
    }

    var elapsedFormatted: String {
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var remainingFormatted: String? {
        guard let remaining = remainingSeconds else { return nil }
        let minutes = remaining / 60
        if minutes < 1 {
            return "<1m"
        }
        return "\(minutes)m"
    }
}

extension Intention {
    static func create(
        text: String,
        durationSeconds: Int?,
        llmFilteringEnabled: Bool = true
    ) -> Intention {
        Intention(
            id: 0, // Will be set by database
            text: text,
            durationSeconds: durationSeconds,
            startedAt: Date(),
            endedAt: nil,
            endReason: nil,
            llmFilteringEnabled: llmFilteringEnabled
        )
    }
}
