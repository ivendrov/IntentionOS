import SwiftUI
import AppKit

struct BreakGlassView: View {
    let type: AccessType
    let identifier: String
    let displayName: String
    let intention: String
    let onDismiss: (Bool, Bool) -> Void // (wasOverride, shouldLearn)
    let onEndIntention: () -> Void // End intention and start new one

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                backgroundView

                // Content
                VStack(spacing: 30) {
                    Spacer()

                    // Warning icon
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.orange)

                    // Message
                    VStack(spacing: 16) {
                        Text("\"\(displayName)\" doesn't seem aligned with your intention:")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        Text("\"\(intention)\"")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 500)

                    Spacer().frame(height: 40)

                    // Buttons
                    VStack(spacing: 16) {
                        Button("Go Back") {
                            onDismiss(false, false)
                        }
                        .buttonStyle(BreakGlassPrimaryButtonStyle())

                        Button(action: onEndIntention) {
                            Text("End intention and start a new one")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Debug hint
                    Text("Hold Escape for 5 seconds to quit")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 40)
            }
        }
    }

    private var backgroundView: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            // Animated orb (red-orange for warning)
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.orange.opacity(0.3),
                            Color.red.opacity(0.2),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 50,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 600)
                .blur(radius: 50)
        }
    }
}

// MARK: - Custom Styles

struct BreakGlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.black)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(20)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Window Controller

class BreakGlassWindowController: NSWindowController {
    let type: AccessType
    let identifier: String
    let displayName: String
    let intentionText: String

    private var escapeKeyDownTime: Date?
    private var escapeCheckTimer: Timer?
    private var focusTimer: Timer?

    convenience init(type: AccessType, identifier: String, displayName: String, intention: String, screen: NSScreen) {
        let window = BreakGlassWindow(screen: screen)
        self.init(window: window, type: type, identifier: identifier, displayName: displayName, intention: intention)

        let hostingView = NSHostingView(
            rootView: BreakGlassView(
                type: type,
                identifier: identifier,
                displayName: displayName,
                intention: intention,
                onDismiss: { [weak self] wasOverride, shouldLearn in
                    self?.handleDismiss(wasOverride: wasOverride, shouldLearn: shouldLearn)
                },
                onEndIntention: { [weak self] in
                    self?.handleEndIntention()
                }
            )
        )
        window.contentView = hostingView

        // Setup escape key monitoring for debug exit
        setupEscapeKeyMonitor()
    }

    init(window: NSWindow, type: AccessType, identifier: String, displayName: String, intention: String) {
        self.type = type
        self.identifier = identifier
        self.displayName = displayName
        self.intentionText = intention
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    private func handleDismiss(wasOverride: Bool, shouldLearn: Bool) {
        // User clicked "Go Back" - switch to the last allowed app
        if let appDelegate = AppDelegate.shared {
            appDelegate.switchToLastAllowedApp()
        }
    }

    private func handleEndIntention() {
        // End the current intention and show the intention prompt
        IntentionManager.shared.endIntention(reason: .newIntention)

        if let appDelegate = AppDelegate.shared {
            appDelegate.closeBreakGlassPrompt()
            appDelegate.switchToLastAllowedApp()
            appDelegate.showIntentionPrompt()
        }
    }
}

// MARK: - Fullscreen Window

class BreakGlassWindow: NSWindow {
    init(screen: NSScreen) {
        // Use the full screen frame
        let frame = screen.frame

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Window configuration - same as IntentionWindow
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = true
        self.hasShadow = false
        self.backgroundColor = .black
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        // Ensure it covers the full screen
        self.setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
