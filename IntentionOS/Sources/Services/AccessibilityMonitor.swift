import AppKit
import ApplicationServices

class AccessibilityMonitor {
    var onAppFocused: ((String, String) -> Void)? // (bundleId, appName)

    private var observer: AXObserver?
    private var lastFocusedApp: String?
    private var workspaceObserver: NSObjectProtocol?

    func startMonitoring() {
        // Check accessibility permissions
        guard checkAccessibilityPermissions() else {
            print("Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return
        }

        // Monitor app activation via NSWorkspace
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }

        // Also check current frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            handleAppChange(app: frontmost)
        }
    }

    func stopMonitoring() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }

    private func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        handleAppChange(app: app)
    }

    private func handleAppChange(app: NSRunningApplication) {
        guard let bundleId = app.bundleIdentifier else { return }

        // Ignore our own app
        if bundleId == Bundle.main.bundleIdentifier { return }

        // Avoid duplicate notifications for the same app
        if bundleId == lastFocusedApp { return }
        lastFocusedApp = bundleId

        let appName = app.localizedName ?? bundleId

        // Notify handler
        onAppFocused?(bundleId, appName)
    }
}

// MARK: - Accessibility Helpers

extension AccessibilityMonitor {
    /// Gets the focused window's title (useful for browser tab detection)
    func getFocusedWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        guard result == .success, let window = focusedWindow else { return nil }

        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)

        guard titleResult == .success, let titleString = title as? String else { return nil }

        return titleString
    }

    /// Gets the URL from Safari's address bar (if Safari is focused)
    func getSafariURL() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.apple.Safari" else {
            return nil
        }

        // Use AppleScript to get Safari URL
        let script = """
        tell application "Safari"
            if (count of windows) > 0 then
                return URL of current tab of front window
            end if
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
                return nil
            }
            return output.stringValue
        }

        return nil
    }

    /// Gets the URL from Chrome (requires extension or AppleScript)
    func getChromeURL() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.google.Chrome" else {
            return nil
        }

        // Use AppleScript to get Chrome URL
        let script = """
        tell application "Google Chrome"
            if (count of windows) > 0 then
                return URL of active tab of front window
            end if
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
                return nil
            }
            return output.stringValue
        }

        return nil
    }
}
