import SwiftUI
import AppKit
import ApplicationServices

// Use traditional AppDelegate as @main instead of SwiftUI App
// This fixes issues with NSStatusItem not appearing
@main
class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    // Shared instance for easy access
    static var shared: AppDelegate?

    var intentionWindowControllers: [IntentionWindowController] = []
    var breakGlassWindowControllers: [BreakGlassWindowController] = []
    var setupWindowController: SetupWindowController?
    var accessibilityMonitor: AccessibilityMonitor?
    var wakeObserver: NSObjectProtocol?
    var loginObserver: NSObjectProtocol?
    var screenChangeObserver: NSObjectProtocol?

    // Track last allowed app for "Go Back" functionality
    var lastAllowedAppBundleId: String?

    // Floating timer window
    var floatingTimerController: FloatingTimerWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Store shared reference
        AppDelegate.shared = self

        // Show dock icon during setup
        NSApp.setActivationPolicy(.regular)

        // Load configuration
        ConfigManager.shared.loadConfig()

        // Initialize database
        DatabaseManager.shared.initialize()

        // Start HTTP server for Chrome extension
        LocalHTTPServer.shared.start()

        // Check accessibility before proceeding
        if hasAccessibilityPermission() {
            setupCompleted()
        } else {
            showSetupWindow()
        }
    }

    private func hasAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func showSetupWindow() {
        setupWindowController = SetupWindowController()
        setupWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setupCompleted() {
        // Close setup window
        setupWindowController?.close()
        setupWindowController = nil

        // Hide dock icon - we're a floating window app
        NSApp.setActivationPolicy(.accessory)

        // End any stale intentions from previous session
        if IntentionManager.shared.currentIntention != nil {
            IntentionManager.shared.endIntention(reason: .newIntention)
        }

        // Setup wake/sleep observers
        setupSystemObservers()

        // Show floating timer window (always visible)
        showFloatingTimer()

        // Show intention prompt FIRST, before starting monitoring
        showIntentionPrompt()

        // Setup accessibility monitoring AFTER showing prompt
        // Use a delay to ensure the prompt is fully visible first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupAccessibilityMonitor()
        }
    }

    func showFloatingTimer() {
        if floatingTimerController == nil {
            floatingTimerController = FloatingTimerWindowController()
        }
        floatingTimerController?.showWindow(nil)
    }

    func hideFloatingTimer() {
        floatingTimerController?.close()
        floatingTimerController = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = loginObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Accessibility

    private func setupAccessibilityMonitor() {
        accessibilityMonitor = AccessibilityMonitor()
        accessibilityMonitor?.onAppFocused = { [weak self] bundleId, appName in
            self?.handleAppFocus(bundleId: bundleId, appName: appName)
        }
        accessibilityMonitor?.startMonitoring()
    }

    // MARK: - System Observers

    private func setupSystemObservers() {
        // Wake from sleep
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake()
        }

        // Screen unlock
        loginObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenUnlock()
        }

        // Screen configuration changes (monitor connected/disconnected)
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }
    }

    private func handleScreenChange() {
        // If the intention prompt is showing, recreate windows to cover all screens
        if !intentionWindowControllers.isEmpty {
            showIntentionPrompt()
        }
        // Same for break-glass windows
        if !breakGlassWindowControllers.isEmpty {
            // Re-show with existing parameters isn't straightforward,
            // but at minimum ensure the existing windows cover their screens
            for controller in breakGlassWindowControllers {
                if let window = controller.window, let screen = window.screen {
                    window.setFrame(screen.frame, display: true)
                }
            }
        }
    }

    private func handleSystemWake() {
        // End any current intention when waking from sleep
        if IntentionManager.shared.currentIntention != nil {
            IntentionManager.shared.endIntention(reason: .newIntention)
        }
        // Show immediately on the primary display, then the screen change
        // observer will pick up any external displays that appear shortly after.
        showIntentionPrompt()
    }

    private func handleScreenUnlock() {
        // End any current intention when unlocking screen
        if IntentionManager.shared.currentIntention != nil {
            IntentionManager.shared.endIntention(reason: .newIntention)
        }
        showIntentionPrompt()
    }

    private func handleAppFocus(bundleId: String, appName: String) {
        // Ignore loginwindow - it's the lock screen, not a real app
        if bundleId == "com.apple.loginwindow" {
            return
        }

        // Don't check apps while the intention prompt is showing
        if !intentionWindowControllers.isEmpty {
            return
        }

        guard let intention = IntentionManager.shared.currentIntention else { return }

        let filterResult = RuleEngine.shared.checkApp(
            bundleId: bundleId,
            appName: appName,
            intention: intention
        )

        if !filterResult.allowed {
            showBreakGlassPrompt(
                type: .app,
                identifier: bundleId,
                displayName: appName,
                intention: intention.text
            )
        } else {
            // Track this as the last allowed app
            lastAllowedAppBundleId = bundleId

            DatabaseManager.shared.logAccess(
                intentionId: intention.id,
                type: .app,
                identifier: bundleId,
                wasAllowed: true,
                allowedReason: filterResult.reason,
                wasOverride: false
            )
        }
    }

    func switchToLastAllowedApp() {
        // Close break glass first
        closeBreakGlassPrompt()

        // Try to activate the last allowed app
        if let bundleId = lastAllowedAppBundleId,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            print("DEBUG: Switching back to \(bundleId)")
            app.activate(options: [.activateIgnoringOtherApps])
        } else {
            // Fallback: activate Finder
            print("DEBUG: No last allowed app, activating Finder")
            if let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
                finder.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    // MARK: - Windows

    func showIntentionPrompt() {
        closeIntentionWindows()

        for screen in NSScreen.screens {
            let controller = IntentionWindowController(screen: screen)
            controller.showWindow(nil)
            intentionWindowControllers.append(controller)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func closeIntentionWindows() {
        print("DEBUG: closeIntentionWindows called, count: \(intentionWindowControllers.count)")
        for controller in intentionWindowControllers {
            print("DEBUG: Closing window controller")
            controller.window?.orderOut(nil)
            controller.close()
        }
        intentionWindowControllers.removeAll()
        print("DEBUG: Windows closed")
    }

    func showBreakGlassPrompt(type: AccessType, identifier: String, displayName: String, intention: String) {
        // Don't show if already showing
        guard breakGlassWindowControllers.isEmpty else { return }

        // Create fullscreen windows on all screens
        for screen in NSScreen.screens {
            let controller = BreakGlassWindowController(
                type: type,
                identifier: identifier,
                displayName: displayName,
                intention: intention,
                screen: screen
            )
            controller.showWindow(nil)
            breakGlassWindowControllers.append(controller)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func closeBreakGlassPrompt() {
        for controller in breakGlassWindowControllers {
            controller.window?.orderOut(nil)
            controller.close()
        }
        breakGlassWindowControllers.removeAll()
    }
}
