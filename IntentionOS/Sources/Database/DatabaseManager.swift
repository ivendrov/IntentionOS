import Foundation
import SQLite3

class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?

    private init() {}

    var databasePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let intentionDir = appSupport.appendingPathComponent("IntentionOS")
        try? FileManager.default.createDirectory(at: intentionDir, withIntermediateDirectories: true)
        return intentionDir.appendingPathComponent("intention.db").path
    }

    func initialize() {
        guard sqlite3_open(databasePath, &db) == SQLITE_OK else {
            print("Failed to open database at \(databasePath)")
            return
        }
        createTables()
        createDefaultBundles()
    }

    private func createDefaultBundles() {
        // Check if Admin bundle already exists
        let existingBundles = getAllBundles()
        if existingBundles.contains(where: { $0.name == "Admin" }) {
            return
        }

        // Create Admin bundle that allows ALL apps and ALL URLs
        let adminBundle = AppBundle(
            id: 0,
            name: "Admin",
            apps: [],  // No specific apps needed - allowAllApps = true
            urlPatterns: [],  // No specific patterns needed - allowAllURLs = true
            allowAllApps: true,  // Allow ANY app
            allowAllURLs: true,  // Allow ANY URL
            createdAt: Date(),
            updatedAt: Date()
        )

        createBundle(adminBundle)
        print("DEBUG: Created default Admin bundle (allows all apps and URLs)")
    }

    private func createTables() {
        let createStatements = """
        CREATE TABLE IF NOT EXISTS intentions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            duration_seconds INTEGER,
            started_at REAL NOT NULL,
            ended_at REAL,
            end_reason TEXT,
            llm_filtering_enabled INTEGER DEFAULT 1
        );

        CREATE TABLE IF NOT EXISTS bundles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            allow_all_apps INTEGER DEFAULT 0,
            allow_all_urls INTEGER DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS bundle_apps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bundle_id INTEGER REFERENCES bundles(id) ON DELETE CASCADE,
            app_bundle_id TEXT NOT NULL,
            app_name TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS bundle_urls (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bundle_id INTEGER REFERENCES bundles(id) ON DELETE CASCADE,
            url_pattern TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS intention_apps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            intention_id INTEGER REFERENCES intentions(id) ON DELETE CASCADE,
            app_bundle_id TEXT NOT NULL,
            app_name TEXT NOT NULL,
            from_bundle_id INTEGER REFERENCES bundles(id)
        );

        CREATE TABLE IF NOT EXISTS intention_urls (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            intention_id INTEGER REFERENCES intentions(id) ON DELETE CASCADE,
            url_pattern TEXT NOT NULL,
            from_bundle_id INTEGER REFERENCES bundles(id)
        );

        CREATE TABLE IF NOT EXISTS intention_bundles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            intention_id INTEGER REFERENCES intentions(id) ON DELETE CASCADE,
            bundle_id INTEGER REFERENCES bundles(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS access_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            intention_id INTEGER REFERENCES intentions(id),
            timestamp REAL NOT NULL,
            type TEXT NOT NULL,
            identifier TEXT NOT NULL,
            was_allowed INTEGER NOT NULL,
            allowed_reason TEXT,
            was_override INTEGER NOT NULL,
            added_to_learned INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS learned_rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            intention_pattern TEXT NOT NULL,
            type TEXT NOT NULL,
            identifier TEXT NOT NULL,
            allowed INTEGER NOT NULL,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS intention_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL UNIQUE,
            times_entered INTEGER DEFAULT 1,
            times_selected INTEGER DEFAULT 0,
            first_entered_at REAL NOT NULL,
            last_used_at REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_intentions_started_at ON intentions(started_at);
        CREATE INDEX IF NOT EXISTS idx_access_log_intention_id ON access_log(intention_id);
        CREATE INDEX IF NOT EXISTS idx_learned_rules_type_identifier ON learned_rules(type, identifier);
        CREATE INDEX IF NOT EXISTS idx_intention_history_last_used ON intention_history(last_used_at DESC);
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createStatements, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("Failed to create tables: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Intentions

    @discardableResult
    func createIntention(_ intention: Intention) -> Int64 {
        let sql = """
        INSERT INTO intentions (text, duration_seconds, started_at, ended_at, end_reason, llm_filtering_enabled)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, intention.text, -1, SQLITE_TRANSIENT)
        if let duration = intention.durationSeconds {
            sqlite3_bind_int(stmt, 2, Int32(duration))
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_double(stmt, 3, intention.startedAt.timeIntervalSince1970)
        if let endedAt = intention.endedAt {
            sqlite3_bind_double(stmt, 4, endedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        if let endReason = intention.endReason {
            sqlite3_bind_text(stmt, 5, endReason.rawValue, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_int(stmt, 6, intention.llmFilteringEnabled ? 1 : 0)

        guard sqlite3_step(stmt) == SQLITE_DONE else { return 0 }
        return sqlite3_last_insert_rowid(db)
    }

    func endIntention(id: Int64, reason: Intention.EndReason) {
        let sql = "UPDATE intentions SET ended_at = ?, end_reason = ? WHERE id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, reason.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, id)

        sqlite3_step(stmt)
    }

    func getActiveIntention() -> Intention? {
        let sql = "SELECT * FROM intentions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return intentionFromStatement(stmt)
    }

    func getRecentIntentions(limit: Int = 50) -> [Intention] {
        let sql = "SELECT * FROM intentions ORDER BY started_at DESC LIMIT ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var intentions: [Intention] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let intention = intentionFromStatement(stmt) {
                intentions.append(intention)
            }
        }
        return intentions
    }

    private func intentionFromStatement(_ stmt: OpaquePointer?) -> Intention? {
        guard let stmt = stmt else { return nil }

        let id = sqlite3_column_int64(stmt, 0)
        let text = String(cString: sqlite3_column_text(stmt, 1))
        let durationSeconds: Int? = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 2))
        let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let endedAt: Date? = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
        let endReason: Intention.EndReason? = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : Intention.EndReason(rawValue: String(cString: sqlite3_column_text(stmt, 5)))
        let llmFilteringEnabled = sqlite3_column_int(stmt, 6) == 1

        return Intention(
            id: id,
            text: text,
            durationSeconds: durationSeconds,
            startedAt: startedAt,
            endedAt: endedAt,
            endReason: endReason,
            llmFilteringEnabled: llmFilteringEnabled
        )
    }

    // MARK: - Bundles

    @discardableResult
    func createBundle(_ bundle: AppBundle) -> Int64 {
        let sql = "INSERT INTO bundles (name, allow_all_apps, allow_all_urls, created_at, updated_at) VALUES (?, ?, ?, ?, ?)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bundle.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, bundle.allowAllApps ? 1 : 0)
        sqlite3_bind_int(stmt, 3, bundle.allowAllURLs ? 1 : 0)
        sqlite3_bind_double(stmt, 4, bundle.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 5, bundle.updatedAt.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else { return 0 }
        let bundleId = sqlite3_last_insert_rowid(db)

        // Insert apps
        for app in bundle.apps {
            addAppToBundle(bundleId: bundleId, app: app)
        }

        // Insert URL patterns
        for pattern in bundle.urlPatterns {
            addURLToBundle(bundleId: bundleId, pattern: pattern)
        }

        return bundleId
    }

    func updateBundle(_ bundle: AppBundle) {
        let sql = "UPDATE bundles SET name = ?, allow_all_apps = ?, allow_all_urls = ?, updated_at = ? WHERE id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bundle.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, bundle.allowAllApps ? 1 : 0)
        sqlite3_bind_int(stmt, 3, bundle.allowAllURLs ? 1 : 0)
        sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 5, bundle.id)

        sqlite3_step(stmt)

        // Clear and re-add apps and URLs
        clearBundleApps(bundleId: bundle.id)
        clearBundleURLs(bundleId: bundle.id)

        for app in bundle.apps {
            addAppToBundle(bundleId: bundle.id, app: app)
        }
        for pattern in bundle.urlPatterns {
            addURLToBundle(bundleId: bundle.id, pattern: pattern)
        }
    }

    func deleteBundle(id: Int64) {
        let sql = "DELETE FROM bundles WHERE id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
    }

    func getAllBundles() -> [AppBundle] {
        let sql = "SELECT id, name, allow_all_apps, allow_all_urls, created_at, updated_at FROM bundles ORDER BY name"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var bundles: [AppBundle] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let allowAllApps = sqlite3_column_int(stmt, 2) == 1
            let allowAllURLs = sqlite3_column_int(stmt, 3) == 1
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))

            let apps = getBundleApps(bundleId: id)
            let urlPatterns = getBundleURLs(bundleId: id)

            bundles.append(AppBundle(
                id: id,
                name: name,
                apps: apps,
                urlPatterns: urlPatterns,
                allowAllApps: allowAllApps,
                allowAllURLs: allowAllURLs,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
        return bundles
    }

    private func addAppToBundle(bundleId: Int64, app: BundleApp) {
        let sql = "INSERT INTO bundle_apps (bundle_id, app_bundle_id, app_name) VALUES (?, ?, ?)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, bundleId)
        sqlite3_bind_text(stmt, 2, app.bundleId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, app.name, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    private func addURLToBundle(bundleId: Int64, pattern: String) {
        let sql = "INSERT INTO bundle_urls (bundle_id, url_pattern) VALUES (?, ?)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, bundleId)
        sqlite3_bind_text(stmt, 2, pattern, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    private func clearBundleApps(bundleId: Int64) {
        let sql = "DELETE FROM bundle_apps WHERE bundle_id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, bundleId)
        sqlite3_step(stmt)
    }

    private func clearBundleURLs(bundleId: Int64) {
        let sql = "DELETE FROM bundle_urls WHERE bundle_id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, bundleId)
        sqlite3_step(stmt)
    }

    private func getBundleApps(bundleId: Int64) -> [BundleApp] {
        let sql = "SELECT app_bundle_id, app_name FROM bundle_apps WHERE bundle_id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, bundleId)

        var apps: [BundleApp] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let bundleId = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            apps.append(BundleApp(bundleId: bundleId, name: name))
        }
        return apps
    }

    private func getBundleURLs(bundleId: Int64) -> [String] {
        let sql = "SELECT url_pattern FROM bundle_urls WHERE bundle_id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, bundleId)

        var patterns: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            patterns.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return patterns
    }

    // MARK: - Intention Apps/URLs

    func addAppToIntention(intentionId: Int64, app: IntentionApp) {
        let sql = "INSERT INTO intention_apps (intention_id, app_bundle_id, app_name, from_bundle_id) VALUES (?, ?, ?, ?)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, intentionId)
        sqlite3_bind_text(stmt, 2, app.bundleId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, app.name, -1, SQLITE_TRANSIENT)
        if let fromBundleId = app.fromBundleId {
            sqlite3_bind_int64(stmt, 4, fromBundleId)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_step(stmt)
    }

    func addURLToIntention(intentionId: Int64, url: IntentionURL) {
        let sql = "INSERT INTO intention_urls (intention_id, url_pattern, from_bundle_id) VALUES (?, ?, ?)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, intentionId)
        sqlite3_bind_text(stmt, 2, url.pattern, -1, SQLITE_TRANSIENT)
        if let fromBundleId = url.fromBundleId {
            sqlite3_bind_int64(stmt, 3, fromBundleId)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_step(stmt)
    }

    func getIntentionApps(intentionId: Int64) -> [IntentionApp] {
        let sql = "SELECT app_bundle_id, app_name, from_bundle_id FROM intention_apps WHERE intention_id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, intentionId)

        var apps: [IntentionApp] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let bundleId = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let fromBundleId: Int64? = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 2)
            apps.append(IntentionApp(bundleId: bundleId, name: name, fromBundleId: fromBundleId))
        }
        return apps
    }

    func getIntentionURLs(intentionId: Int64) -> [IntentionURL] {
        let sql = "SELECT url_pattern, from_bundle_id FROM intention_urls WHERE intention_id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, intentionId)

        var urls: [IntentionURL] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let pattern = String(cString: sqlite3_column_text(stmt, 0))
            let fromBundleId: Int64? = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 1)
            urls.append(IntentionURL(pattern: pattern, fromBundleId: fromBundleId))
        }
        return urls
    }

    // MARK: - Intention Bundles

    func addBundleToIntention(intentionId: Int64, bundleId: Int64) {
        let sql = "INSERT INTO intention_bundles (intention_id, bundle_id) VALUES (?, ?)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, intentionId)
        sqlite3_bind_int64(stmt, 2, bundleId)
        sqlite3_step(stmt)
    }

    func getIntentionBundleIds(intentionId: Int64) -> Set<Int64> {
        let sql = "SELECT bundle_id FROM intention_bundles WHERE intention_id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, intentionId)

        var bundleIds: Set<Int64> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            bundleIds.insert(sqlite3_column_int64(stmt, 0))
        }
        return bundleIds
    }

    // MARK: - Access Log

    func logAccess(intentionId: Int64, type: AccessType, identifier: String, wasAllowed: Bool, allowedReason: AllowedReason?, wasOverride: Bool) {
        let sql = """
        INSERT INTO access_log (intention_id, timestamp, type, identifier, was_allowed, allowed_reason, was_override, added_to_learned)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, intentionId)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, type.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, identifier, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, wasAllowed ? 1 : 0)
        if let reason = allowedReason {
            sqlite3_bind_text(stmt, 6, reason.rawValue, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_int(stmt, 7, wasOverride ? 1 : 0)

        sqlite3_step(stmt)
    }

    // MARK: - Learned Rules

    func addLearnedRule(intentionPattern: String, type: AccessType, identifier: String, allowed: Bool) {
        let sql = "INSERT INTO learned_rules (intention_pattern, type, identifier, allowed, created_at) VALUES (?, ?, ?, ?, ?)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, intentionPattern, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, type.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, identifier, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, allowed ? 1 : 0)
        sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)

        sqlite3_step(stmt)
    }

    func findLearnedRule(type: AccessType, identifier: String) -> LearnedRule? {
        let sql = "SELECT * FROM learned_rules WHERE type = ? AND identifier = ? ORDER BY created_at DESC LIMIT 1"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, type.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, identifier, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        return LearnedRule(
            id: sqlite3_column_int64(stmt, 0),
            intentionPattern: String(cString: sqlite3_column_text(stmt, 1)),
            type: AccessType(rawValue: String(cString: sqlite3_column_text(stmt, 2)))!,
            identifier: String(cString: sqlite3_column_text(stmt, 3)),
            allowed: sqlite3_column_int(stmt, 4) == 1,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
        )
    }

    // MARK: - Intention History

    /// Record that an intention text was entered (may or may not be selected)
    func recordIntentionEntered(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        guard !trimmedText.isEmpty else { return }

        let now = Date().timeIntervalSince1970

        // Try to update existing record first
        let updateSql = """
        UPDATE intention_history
        SET times_entered = times_entered + 1, last_used_at = ?
        WHERE text = ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSql, -1, &stmt, nil) == SQLITE_OK else { return }

        sqlite3_bind_double(stmt, 1, now)
        sqlite3_bind_text(stmt, 2, trimmedText, -1, SQLITE_TRANSIENT)

        sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        // If no row was updated, insert new
        if sqlite3_changes(db) == 0 {
            let insertSql = """
            INSERT INTO intention_history (text, times_entered, times_selected, first_entered_at, last_used_at)
            VALUES (?, 1, 0, ?, ?)
            """

            guard sqlite3_prepare_v2(db, insertSql, -1, &stmt, nil) == SQLITE_OK else { return }

            sqlite3_bind_text(stmt, 1, trimmedText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, now)
            sqlite3_bind_double(stmt, 3, now)

            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// Record that an intention was selected (chosen to work on)
    func recordIntentionSelected(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        guard !trimmedText.isEmpty else { return }

        let now = Date().timeIntervalSince1970

        let sql = """
        UPDATE intention_history
        SET times_selected = times_selected + 1, last_used_at = ?
        WHERE text = ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, now)
        sqlite3_bind_text(stmt, 2, trimmedText, -1, SQLITE_TRANSIENT)

        sqlite3_step(stmt)
    }

    /// Get recent intention history, ordered by last used
    func getIntentionHistory(limit: Int = 100) -> [IntentionHistoryItem] {
        let sql = """
        SELECT id, text, times_entered, times_selected, first_entered_at, last_used_at
        FROM intention_history
        ORDER BY last_used_at DESC
        LIMIT ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var items: [IntentionHistoryItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let item = IntentionHistoryItem(
                id: sqlite3_column_int64(stmt, 0),
                text: String(cString: sqlite3_column_text(stmt, 1)),
                timesEntered: Int(sqlite3_column_int(stmt, 2)),
                timesSelected: Int(sqlite3_column_int(stmt, 3)),
                firstEnteredAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                lastUsedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            )
            items.append(item)
        }

        return items
    }

    deinit {
        sqlite3_close(db)
    }
}

/// Model for intention history items
struct IntentionHistoryItem: Identifiable {
    let id: Int64
    let text: String
    let timesEntered: Int
    let timesSelected: Int
    let firstEnteredAt: Date
    let lastUsedAt: Date
}

// MARK: - SQLite Helpers

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
