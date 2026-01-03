import SwiftUI
import AppKit
import ApplicationServices

struct SetupView: View {
    @State private var accessibilityGranted = false
    @State private var checkTimer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "target")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Intention OS")
                .font(.largeTitle.bold())

            Text("Before we begin, we need accessibility permission to monitor which apps you're using.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(accessibilityGranted ? .green : .secondary)
                    Text("Accessibility Permission")
                        .fontWeight(accessibilityGranted ? .semibold : .regular)
                }

                Text("This allows Intention OS to see which app is focused, so it can check if it matches your intention.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .frame(maxWidth: 400)

            if accessibilityGranted {
                Button("Continue") {
                    startApp()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button("Open System Preferences") {
                    openAccessibilityPreferences()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("After granting permission, this window will update automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
        .frame(width: 500, height: 450)
        .onAppear {
            checkAccessibility()
            startCheckTimer()
        }
        .onDisappear {
            checkTimer?.invalidate()
        }
    }

    private func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityGranted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func startCheckTimer() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkAccessibility()
        }
    }

    private func openAccessibilityPreferences() {
        // First, prompt the system to add us to the list
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)

        // Then open System Preferences
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startApp() {
        if let appDelegate = AppDelegate.shared {
            appDelegate.setupCompleted()
        }
    }
}

class SetupWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Intention OS Setup"
        window.center()

        self.init(window: window)

        window.contentView = NSHostingView(rootView: SetupView())
    }
}
