import Foundation

struct AppBundle: Identifiable, Codable, Hashable {
    let id: Int64
    var name: String
    var apps: [BundleApp]
    var urlPatterns: [String]
    var allowAllApps: Bool  // When true, allows ALL apps (not just listed ones)
    var allowAllURLs: Bool  // When true, allows ALL URLs (not just listed patterns)
    var createdAt: Date
    var updatedAt: Date

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AppBundle, rhs: AppBundle) -> Bool {
        lhs.id == rhs.id
    }
}

struct BundleApp: Codable, Hashable, Identifiable {
    var id: String { bundleId }
    let bundleId: String
    let name: String
}

extension AppBundle {
    static func create(
        name: String,
        apps: [BundleApp] = [],
        urlPatterns: [String] = [],
        allowAllApps: Bool = false,
        allowAllURLs: Bool = false
    ) -> AppBundle {
        let now = Date()
        return AppBundle(
            id: 0, // Will be set by database
            name: name,
            apps: apps,
            urlPatterns: urlPatterns,
            allowAllApps: allowAllApps,
            allowAllURLs: allowAllURLs,
            createdAt: now,
            updatedAt: now
        )
    }
}

// For intention-specific apps/URLs not from a bundle
struct IntentionApp: Codable, Hashable, Identifiable {
    var id: String { bundleId }
    let bundleId: String
    let name: String
    let fromBundleId: Int64? // nil if added ad-hoc
}

struct IntentionURL: Codable, Hashable, Identifiable {
    var id: String { pattern }
    let pattern: String
    let fromBundleId: Int64? // nil if added ad-hoc
}
