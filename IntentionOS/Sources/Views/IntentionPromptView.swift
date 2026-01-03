import SwiftUI

struct IntentionPromptView: View {
    @EnvironmentObject var intentionManager: IntentionManager
    @StateObject private var viewModel = IntentionPromptViewModel()

    @State private var intentionText: String = ""
    @State private var selectedDuration: DurationOption = .twentyFive
    @State private var customMinutes: String = ""
    @State private var llmFilteringEnabled: Bool = true
    @State private var intentionConfirmed: Bool = false  // Shows options after Enter

    // Selected items for the intention
    @State private var selectedBundles: Set<Int64> = []
    @State private var selectedApps: [BundleApp] = []
    @State private var urlPatterns: [String] = []

    // Remove escape phrase - not needed when setting an intention

    enum DurationOption: CaseIterable {
        case five
        case ten
        case twentyFive
        case sixty
        case unlimited
        case custom

        var displayText: String {
            switch self {
            case .five: return "5"
            case .ten: return "10"
            case .twentyFive: return "25"
            case .sixty: return "60"
            case .unlimited: return "∞"
            case .custom: return "..."
            }
        }

        var minutes: Int? {
            switch self {
            case .five: return 5
            case .ten: return 10
            case .twentyFive: return 25
            case .sixty: return 60
            case .unlimited: return nil
            case .custom: return nil  // Will use customMinutes
            }
        }
    }

    var isCheckinMode: Bool {
        intentionManager.needsCheckin
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                backgroundView

                // Content - use ScrollView for safety
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        Spacer(minLength: geometry.size.height * 0.15)

                        if isCheckinMode {
                            checkinContent
                        } else {
                            intentionContent
                        }

                        Spacer(minLength: 40)

                        // Debug hint
                        Text("Hold Escape for 5 seconds to quit")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .frame(minHeight: geometry.size.height)
                    .padding(.horizontal, 40)
                }
            }
        }
        .onAppear {
            viewModel.loadBundles()
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            // Animated orb (simplified for Phase 1)
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.3),
                            Color.blue.opacity(0.2),
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

    // MARK: - Checkin Content

    private var checkinContent: some View {
        VStack(spacing: 24) {
            Text("Still working on your intention?")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white)

            if let intention = intentionManager.currentIntention {
                Text("\"\(intention.text)\"")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)

                Text("Time elapsed: \(intentionManager.elapsedTime)")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }

            HStack(spacing: 16) {
                Button("Continue") {
                    intentionManager.acknowledgeCheckin()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Set New Intention") {
                    intentionManager.endIntention(reason: .checkinContinue)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: - Intention Content

    private var intentionContent: some View {
        VStack(spacing: 20) {
            Text("My intention is")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white)

            // Intention text field - press Enter to confirm
            TextField("", text: $intentionText, onCommit: {
                if !intentionText.trimmingCharacters(in: .whitespaces).isEmpty {
                    withAnimation(.easeOut(duration: 0.3)) {
                        intentionConfirmed = true
                    }
                }
            })
            .textFieldStyle(IntentionTextFieldStyle())
            .font(.system(size: 20))
            .frame(maxWidth: 500)

            // Only show options after intention is confirmed
            if intentionConfirmed {
                // Duration selector - compact horizontal
                HStack(spacing: 12) {
                    Text("Duration (min):")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 14))

                    ForEach(DurationOption.allCases, id: \.self) { option in
                        Button(action: { selectedDuration = option }) {
                            Text(option.displayText)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 36, height: 36)
                                .background(selectedDuration == option ? Color.white : Color.white.opacity(0.15))
                                .foregroundColor(selectedDuration == option ? .black : .white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }

                    // Custom minutes input
                    if selectedDuration == .custom {
                        TextField("min", text: $customMinutes)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 50)
                            .padding(8)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(8)
                            .multilineTextAlignment(.center)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Apps & Sites panel (auto-expanded)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apps & Bundles")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 14, weight: .medium))

                    appsSitesPanel
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .frame(maxWidth: 500)
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Begin button
                Button(action: startIntention) {
                    Text("Begin")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 200, height: 50)
                        .background(Color.white)
                        .cornerRadius(25)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Apps & Sites Panel

    private var appsSitesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Bundles
            VStack(alignment: .leading, spacing: 6) {
                Text("Bundles")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.bundles) { bundle in
                            BundleChip(
                                bundle: bundle,
                                isSelected: selectedBundles.contains(bundle.id)
                            ) {
                                if selectedBundles.contains(bundle.id) {
                                    selectedBundles.remove(bundle.id)
                                } else {
                                    selectedBundles.insert(bundle.id)
                                }
                            }
                        }

                        // Add new bundle button
                        Button(action: { viewModel.showBundleManager = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Manage")
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Apps
            VStack(alignment: .leading, spacing: 6) {
                Text("Additional Apps")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedApps) { app in
                            AppChip(app: app) {
                                selectedApps.removeAll { $0.bundleId == app.bundleId }
                            }
                        }

                        Button(action: { viewModel.showAppPicker = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Add App")
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // URLs
            VStack(alignment: .leading, spacing: 6) {
                Text("URL Patterns")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(urlPatterns, id: \.self) { pattern in
                            URLChip(pattern: pattern) {
                                urlPatterns.removeAll { $0 == pattern }
                            }
                        }

                        Button(action: { viewModel.showURLInput = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Add URL")
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().background(Color.white.opacity(0.2))

            // LLM toggle
            Toggle(isOn: $llmFilteringEnabled) {
                Text("Allow LLM-approved apps/sites")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
        }
        .sheet(isPresented: $viewModel.showBundleManager) {
            BundleManagerView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $viewModel.showAppPicker) {
            AppPickerView { app in
                if !selectedApps.contains(where: { $0.bundleId == app.bundleId }) {
                    selectedApps.append(app)
                }
            }
        }
        .sheet(isPresented: $viewModel.showURLInput) {
            URLInputView { pattern in
                if !urlPatterns.contains(pattern) {
                    urlPatterns.append(pattern)
                }
            }
        }
    }

    // MARK: - Actions

    private func startIntention() {
        let trimmedText = intentionText.trimmingCharacters(in: .whitespaces)
        guard !trimmedText.isEmpty else { return }

        // Calculate duration
        let durationMinutes: Int?
        switch selectedDuration {
        case .unlimited:
            durationMinutes = nil
        case .custom:
            if let customValue = Int(customMinutes), customValue > 0 {
                durationMinutes = customValue
            } else {
                durationMinutes = 25  // Default if custom is invalid
            }
        default:
            durationMinutes = selectedDuration.minutes
        }

        let apps = selectedApps.map { IntentionApp(bundleId: $0.bundleId, name: $0.name, fromBundleId: nil) }
        let urls = urlPatterns.map { IntentionURL(pattern: $0, fromBundleId: nil) }

        print("DEBUG: Starting intention: \(trimmedText) for \(durationMinutes ?? -1) minutes")

        intentionManager.startIntention(
            text: trimmedText,
            durationMinutes: durationMinutes,
            apps: apps,
            urls: urls,
            bundleIds: selectedBundles,
            llmFilteringEnabled: llmFilteringEnabled
        )
    }
}

// MARK: - View Model

class IntentionPromptViewModel: ObservableObject {
    @Published var bundles: [AppBundle] = []
    @Published var showBundleManager = false
    @Published var showAppPicker = false
    @Published var showURLInput = false

    func loadBundles() {
        bundles = DatabaseManager.shared.getAllBundles()
    }
}

// MARK: - Custom Styles

struct IntentionTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(Color.white.opacity(0.1))
            .cornerRadius(10)
            .foregroundColor(.white)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
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

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.2))
            .cornerRadius(20)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

// MARK: - Chip Views

struct BundleChip: View {
    let bundle: AppBundle
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10))
                }
                Text(bundle.name)
                    .font(.system(size: 13))
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.white : Color.white.opacity(0.15))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct AppChip: View {
    let app: BundleApp
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(app.name)
                .font(.system(size: 13))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.15))
        .cornerRadius(14)
    }
}

struct URLChip: View {
    let pattern: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(pattern)
                .font(.system(size: 13))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.15))
        .cornerRadius(14)
    }
}
