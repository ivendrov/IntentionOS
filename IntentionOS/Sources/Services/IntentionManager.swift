import Foundation
import Combine
import AppKit
import UserNotifications

class IntentionManager: ObservableObject {
    static let shared = IntentionManager()

    // MARK: - Published State

    @Published private(set) var currentIntention: Intention?
    @Published private(set) var remainingTime: String = ""
    @Published private(set) var elapsedTime: String = ""
    @Published private(set) var isUnlimitedMode: Bool = false
    @Published private(set) var needsCheckin: Bool = false

    // Current intention's explicit apps and URLs
    @Published private(set) var intentionApps: [IntentionApp] = []
    @Published private(set) var intentionURLs: [IntentionURL] = []
    @Published private(set) var selectedBundles: Set<Int64> = []

    // MARK: - Private State

    private var timer: Timer?
    private var lastCheckinTime: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Load any active intention from database
        loadActiveIntention()
    }

    // MARK: - Public Methods

    func startIntention(
        text: String,
        durationMinutes: Int?, // nil = unlimited
        apps: [IntentionApp] = [],
        urls: [IntentionURL] = [],
        bundleIds: Set<Int64> = [],
        llmFilteringEnabled: Bool = true
    ) {
        // End any existing intention
        if currentIntention != nil {
            endIntention(reason: .newIntention)
        }

        // Create new intention
        let durationSeconds = durationMinutes.map { $0 * 60 }
        var intention = Intention.create(
            text: text,
            durationSeconds: durationSeconds,
            llmFilteringEnabled: llmFilteringEnabled
        )

        // Save to database
        let id = DatabaseManager.shared.createIntention(intention)
        intention = Intention(
            id: id,
            text: intention.text,
            durationSeconds: intention.durationSeconds,
            startedAt: intention.startedAt,
            endedAt: nil,
            endReason: nil,
            llmFilteringEnabled: intention.llmFilteringEnabled
        )

        // Save explicit apps/URLs and bundles
        for app in apps {
            DatabaseManager.shared.addAppToIntention(intentionId: id, app: app)
        }
        for url in urls {
            DatabaseManager.shared.addURLToIntention(intentionId: id, url: url)
        }

        // Save selected bundle IDs (important for bundles with allowAllApps/allowAllURLs)
        for bundleId in bundleIds {
            DatabaseManager.shared.addBundleToIntention(intentionId: id, bundleId: bundleId)
        }

        // Add apps/URLs from selected bundles
        let allBundles = DatabaseManager.shared.getAllBundles()
        for bundleId in bundleIds {
            if let bundle = allBundles.first(where: { $0.id == bundleId }) {
                for app in bundle.apps {
                    let intentionApp = IntentionApp(bundleId: app.bundleId, name: app.name, fromBundleId: bundleId)
                    DatabaseManager.shared.addAppToIntention(intentionId: id, app: intentionApp)
                }
                for pattern in bundle.urlPatterns {
                    let intentionURL = IntentionURL(pattern: pattern, fromBundleId: bundleId)
                    DatabaseManager.shared.addURLToIntention(intentionId: id, url: intentionURL)
                }
            }
        }

        // Update state
        currentIntention = intention
        intentionApps = DatabaseManager.shared.getIntentionApps(intentionId: id)
        intentionURLs = DatabaseManager.shared.getIntentionURLs(intentionId: id)
        selectedBundles = bundleIds
        isUnlimitedMode = durationSeconds == nil
        needsCheckin = false
        lastCheckinTime = Date()

        // Start timer
        startTimer()

        // Close intention prompt windows on main thread
        DispatchQueue.main.async {
            print("DEBUG: Attempting to close windows...")
            if let appDelegate = AppDelegate.shared {
                print("DEBUG: Got AppDelegate, closing windows")
                appDelegate.closeIntentionWindows()

                // Open Obsidian (journal) to start fresh
                // This prevents seeing a disallowed app that might distract
                self.openJournalApp()
            } else {
                print("DEBUG: Failed to get AppDelegate.shared")
            }
        }
    }

    /// Opens the journal app (Obsidian) when starting a new intention
    private func openJournalApp() {
        let obsidianBundleId = "md.obsidian"

        // Try to find and activate Obsidian
        if let obsidianApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == obsidianBundleId }) {
            // Obsidian is already running, just activate it
            obsidianApp.activate(options: [.activateIgnoringOtherApps])
        } else {
            // Try to launch Obsidian
            if let obsidianURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: obsidianBundleId) {
                NSWorkspace.shared.openApplication(at: obsidianURL, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                    if let error = error {
                        print("DEBUG: Failed to open Obsidian: \(error)")
                    }
                }
            } else {
                print("DEBUG: Obsidian not found")
            }
        }

        // Track Obsidian as the last allowed app
        if let appDelegate = AppDelegate.shared {
            appDelegate.lastAllowedAppBundleId = obsidianBundleId
        }
    }

    func endIntention(reason: Intention.EndReason) {
        guard let intention = currentIntention else { return }

        DatabaseManager.shared.endIntention(id: intention.id, reason: reason)

        currentIntention = nil
        intentionApps = []
        intentionURLs = []
        selectedBundles = []
        isUnlimitedMode = false
        needsCheckin = false

        stopTimer()

        // Show intention prompt
        if let appDelegate = AppDelegate.shared {
            appDelegate.showIntentionPrompt()
        }
    }

    func acknowledgeCheckin() {
        needsCheckin = false
        lastCheckinTime = Date()

        // Close intention prompt windows
        if let appDelegate = AppDelegate.shared {
            appDelegate.closeIntentionWindows()
        }
    }

    func choseDistraction() {
        endIntention(reason: .choseDistraction)
    }

    // MARK: - App/URL Checking

    func isAppAllowed(bundleId: String) -> FilterResult {
        guard let intention = currentIntention else {
            return .allow(reason: .alwaysAllowed, message: "No active intention")
        }

        return RuleEngine.shared.checkApp(bundleId: bundleId, appName: "", intention: intention)
    }

    func isURLAllowed(url: String) -> FilterResult {
        guard let intention = currentIntention else {
            return .allow(reason: .alwaysAllowed, message: "No active intention")
        }

        return RuleEngine.shared.checkURL(url: url, intention: intention)
    }

    // MARK: - Private Methods

    private func loadActiveIntention() {
        guard let intention = DatabaseManager.shared.getActiveIntention() else { return }

        // Check if it's expired
        if intention.isExpired {
            DatabaseManager.shared.endIntention(id: intention.id, reason: .completed)
            return
        }

        currentIntention = intention
        intentionApps = DatabaseManager.shared.getIntentionApps(intentionId: intention.id)
        intentionURLs = DatabaseManager.shared.getIntentionURLs(intentionId: intention.id)

        // Determine which bundles are active
        let bundleIds = Set(intentionApps.compactMap { $0.fromBundleId } + intentionURLs.compactMap { $0.fromBundleId })
        selectedBundles = bundleIds

        isUnlimitedMode = intention.durationSeconds == nil
        lastCheckinTime = intention.startedAt

        startTimer()
    }

    private func startTimer() {
        stopTimer()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
        timer?.tolerance = 0.1

        updateTimer()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        remainingTime = ""
        elapsedTime = ""
    }

    private func updateTimer() {
        guard let intention = currentIntention else { return }

        elapsedTime = intention.elapsedFormatted

        if let remaining = intention.remainingFormatted {
            remainingTime = remaining

            // Check for expiration
            if let remainingSeconds = intention.remainingSeconds, remainingSeconds <= 0 {
                endIntention(reason: .completed)
                return
            }

            // Check for 5-minute warning
            if let remainingSeconds = intention.remainingSeconds,
               remainingSeconds <= ConfigManager.shared.appConfig.warningBeforeEndMinutes * 60,
               remainingSeconds > (ConfigManager.shared.appConfig.warningBeforeEndMinutes * 60 - 1) {
                sendWarningNotification()
            }
        } else {
            remainingTime = "Unlimited"

            // Check for unlimited mode check-in
            if isUnlimitedMode, let lastCheckin = lastCheckinTime {
                let elapsed = Date().timeIntervalSince(lastCheckin)
                let checkinInterval = TimeInterval(ConfigManager.shared.appConfig.unlimitedCheckinMinutes * 60)

                if elapsed >= checkinInterval {
                    needsCheckin = true
                    if let appDelegate = AppDelegate.shared {
                        appDelegate.showIntentionPrompt()
                    }
                }
            }
        }
    }

    private func sendWarningNotification() {
        guard let intention = currentIntention else { return }

        let content = UNMutableNotificationContent()
        content.title = "Intention OS"
        content.body = "\(ConfigManager.shared.appConfig.warningBeforeEndMinutes) minutes remaining on: \(intention.text)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
