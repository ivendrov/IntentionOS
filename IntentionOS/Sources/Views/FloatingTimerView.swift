import SwiftUI
import AppKit

/// A small floating window that shows the current intention and timer
/// This is a fallback for when the menu bar item doesn't work
struct FloatingTimerView: View {
    @EnvironmentObject var intentionManager: IntentionManager

    private let maxIntentionLength = 50

    private var displayIntention: String {
        guard let intention = intentionManager.currentIntention else { return "" }
        if intention.text.count > maxIntentionLength {
            return String(intention.text.prefix(maxIntentionLength - 1)) + "…"
        }
        return intention.text
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(intentionManager.currentIntention != nil ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            if intentionManager.currentIntention != nil {
                Text(displayIntention)
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize() // Never truncate

                if !intentionManager.remainingTime.isEmpty {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(intentionManager.remainingTime)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .fixedSize() // Never truncate the timer
                }
            } else {
                Text("No intention set")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .fixedSize() // Size to content, never truncate
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
}

class FloatingTimerWindowController: NSWindowController, NSWindowDelegate {
    private var updateTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    convenience init() {
        let window = FloatingTimerWindow()
        self.init(window: window)

        let hostingView = NSHostingView(
            rootView: FloatingTimerView()
                .environmentObject(IntentionManager.shared)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = hostingView

        // Size window to fit content
        let fittingSize = hostingView.fittingSize
        window.setContentSize(fittingSize)

        window.delegate = self

        // Update size and check fullscreen periodically
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateSizeAndPosition()
            self?.updateFullscreenVisibility()
        }

        // Observe space changes for fullscreen detection
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateFullscreenVisibility()
        })

        // Observe app activation for fullscreen detection
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateFullscreenVisibility()
        })

        // Observe screen parameter changes (e.g., entering/exiting fullscreen)
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateFullscreenVisibility()
            self?.updateSizeAndPosition()
        })
    }

    deinit {
        updateTimer?.invalidate()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Check if any app is currently in fullscreen mode
    private func isFullscreenAppActive() -> Bool {
        guard let screen = NSScreen.main else { return false }

        // Method 1: Check if visibleFrame equals frame (no menu bar/dock space)
        // This indicates we're on a fullscreen space
        let menuBarHeight = screen.frame.height - screen.visibleFrame.height - screen.visibleFrame.origin.y
        if menuBarHeight < 1 {
            return true
        }

        // Method 2: Check NSMenu.menuBarVisible()
        if !NSMenu.menuBarVisible() {
            return true
        }

        return false
    }

    private func updateFullscreenVisibility() {
        guard let window = window else { return }

        if isFullscreenAppActive() {
            // Hide the floating timer during fullscreen
            if window.isVisible {
                window.orderOut(nil)
            }
        } else {
            // Show the floating timer when not fullscreen
            if !window.isVisible {
                window.orderFront(nil)
            }
        }
    }

    func updateSizeAndPosition() {
        guard let window = window,
              let hostingView = window.contentView as? NSHostingView<AnyView> ?? window.contentView as? NSView,
              let screen = NSScreen.main else { return }

        // Get the fitting size from the hosting view
        let fittingSize = hostingView.fittingSize

        // Only resize if needed
        if abs(window.frame.size.width - fittingSize.width) > 1 ||
           abs(window.frame.size.height - fittingSize.height) > 1 {
            window.setContentSize(fittingSize)
        }

        // Position in top-right corner, tight to the edge
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let x = screenFrame.maxX - windowSize.width - 4
        let y = screenFrame.maxY - windowSize.height - 4

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        updateSizeAndPosition()
        updateFullscreenVisibility()
    }
}

class FloatingTimerWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 30),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        // Don't use .canJoinAllSpaces - it forces window onto fullscreen spaces
        // Use .moveToActiveSpace so it follows when switching regular spaces
        self.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false

        // Allow clicking through when not hovering
        self.isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
