import AppKit
import SwiftUI

class IntentionWindowController: NSWindowController {
    private var escapeKeyDownTime: Date?
    private var escapeCheckTimer: Timer?
    private var focusTimer: Timer?

    convenience init(screen: NSScreen) {
        let window = IntentionWindow(screen: screen)
        self.init(window: window)

        let hostingView = NSHostingView(
            rootView: IntentionPromptView()
                .environmentObject(IntentionManager.shared)
        )
        window.contentView = hostingView

        // Setup escape key monitoring for debug exit
        setupEscapeKeyMonitor()
    }

    private func setupEscapeKeyMonitor() {
        // Monitor for Escape key hold (5 seconds to quit)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                if self?.escapeKeyDownTime == nil {
                    self?.escapeKeyDownTime = Date()
                    self?.startEscapeCheckTimer()
                }
            }
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.escapeKeyDownTime = nil
                self?.escapeCheckTimer?.invalidate()
                self?.escapeCheckTimer = nil
            }
            return event
        }
    }

    private func startEscapeCheckTimer() {
        escapeCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let downTime = self?.escapeKeyDownTime else { return }
            let elapsed = Date().timeIntervalSince(downTime)
            if elapsed >= 5.0 {
                // Emergency exit after holding Escape for 5 seconds
                print("DEBUG: Emergency exit triggered by holding Escape")
                NSApp.terminate(nil)
            }
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        startFocusReassertionTimer()
    }

    private func startFocusReassertionTimer() {
        let delay = TimeInterval(ConfigManager.shared.appConfig.reassertFocusDelayMs) / 1000.0

        focusTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: true) { [weak self] _ in
            guard let window = self?.window, window.isVisible else {
                self?.focusTimer?.invalidate()
                return
            }

            if !window.isKeyWindow {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    override func close() {
        focusTimer?.invalidate()
        focusTimer = nil
        escapeCheckTimer?.invalidate()
        escapeCheckTimer = nil
        super.close()
    }
}

class IntentionWindow: NSWindow {
    init(screen: NSScreen) {
        // Use the visible frame (excludes menu bar and dock)
        let visibleFrame = screen.visibleFrame

        super.init(
            contentRect: visibleFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Window configuration
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = true
        self.hasShadow = false
        self.backgroundColor = .black
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        // Use the full screen frame, not just visible
        self.setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Allow close during development - will tighten later
    override func close() {
        super.close()
    }

    override func performClose(_ sender: Any?) {
        // Allow Cmd+W during development
        super.close()
    }
}
