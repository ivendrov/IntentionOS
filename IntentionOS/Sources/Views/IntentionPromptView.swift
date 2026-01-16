import SwiftUI

// Entry for each intention with its weight
struct IntentionEntry: Identifiable {
    let id = UUID()
    var text: String
    var pips: Int

    init(text: String = "", pips: Int = 1) {
        self.text = text
        self.pips = pips
    }
}

struct IntentionPromptView: View {
    @EnvironmentObject var intentionManager: IntentionManager
    @StateObject private var viewModel = IntentionPromptViewModel()

    // Multiple intentions flow
    @State private var intentions: [IntentionEntry] = [IntentionEntry(), IntentionEntry()]
    @State private var flowPhase: FlowPhase = .enteringIntentions
    @State private var selectedIntentionIndex: Int? = nil
    @State private var finalIntentionText: String = ""

    enum FlowPhase {
        case enteringIntentions  // User enters 2-6 intentions
        case selectingIntention  // User picks one or randomizes
        case configuringDetails  // Duration, apps, bundles
    }

    @State private var selectedDuration: DurationOption = .twentyFive
    @State private var customMinutes: String = ""
    @State private var llmFilteringEnabled: Bool = true

    // Selected items for the intention
    @State private var selectedBundles: Set<Int64> = []
    @State private var selectedApps: [BundleApp] = []
    @State private var urlPatterns: [String] = []

    // Mindful pause - 10 second countdown before Begin is enabled
    @State private var countdownRemaining: Double = 10.0
    @State private var countdownActive: Bool = true
    @State private var countdownTimer: Timer?

    // Animation states - ripples like light rain
    @State private var ripples: [RippleState] = []
    @State private var ambientPhase: Double = 0
    @State private var rainTimer: Timer?

    // Intention history
    @State private var intentionHistory: [IntentionHistoryItem] = []

    // Computed properties for validation
    private var validIntentions: [IntentionEntry] {
        intentions.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var canProceedToSelection: Bool {
        validIntentions.count >= 2
    }

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
                // Background with top-down water ripples (light rain effect)
                RippleBackground(ripples: ripples, ambientPhase: ambientPhase, geometry: geometry)
                    .edgesIgnoringSafeArea(.all)

                // Edge progress ring during countdown (only in entering phase)
                if countdownActive && flowPhase == .enteringIntentions {
                    EdgeProgressRing(progress: 1.0 - (countdownRemaining / 10.0), geometry: geometry)
                }

                // Content - use ScrollView for safety
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        Spacer(minLength: geometry.size.height * 0.1)

                        if isCheckinMode {
                            checkinContent
                        } else {
                            switch flowPhase {
                            case .enteringIntentions:
                                enterIntentionsContent
                            case .selectingIntention:
                                selectIntentionContent
                            case .configuringDetails:
                                configureDetailsContent
                            }
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
            startAnimations()
            loadIntentionHistory()
            startCountdown()  // Start mindful pause immediately
        }
        .onDisappear {
            stopAnimations()
        }
    }

    private func addTypingRipple() {
        let newRipple = RippleState(id: UUID(), startTime: Date(), x: 0.5, y: 0.35)
        ripples.append(newRipple)

        // Remove old ripples after they fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            ripples.removeAll { $0.id == newRipple.id }
        }
    }

    // MARK: - Animation Control

    private func startAnimations() {
        // Ambient phase for background movement
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            ambientPhase += 0.008
        }

        // Rain effect - add random ripples periodically
        rainTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            addRainRipple()
        }

        // Start with a few ripples already visible
        for _ in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0...0.5)) {
                addRainRipple()
            }
        }
    }

    private func addRainRipple() {
        let newRipple = RippleState(
            id: UUID(),
            startTime: Date(),
            x: Double.random(in: 0.1...0.9),
            y: Double.random(in: 0.1...0.9)
        )
        ripples.append(newRipple)

        // Remove after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            ripples.removeAll { $0.id == newRipple.id }
        }
    }

    private func startCountdown() {
        countdownRemaining = 10.0
        countdownActive = true

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if countdownRemaining > 0 {
                countdownRemaining -= 0.1
            } else {
                countdownActive = false
                timer.invalidate()
            }
        }
    }

    private func stopAnimations() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        rainTimer?.invalidate()
        rainTimer = nil
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

    // MARK: - Phase 1: Enter Multiple Intentions

    private var enterIntentionsContent: some View {
        HStack(alignment: .top, spacing: 0) {
            // History sidebar on the left
            if !intentionHistory.isEmpty {
                intentionHistorySidebar
                    .frame(width: 220)
                    .padding(.trailing, 40)
            }

            // Main content
            VStack(spacing: 24) {
                Text("What could you do?")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.white)

                Text("Enter at least 2 intentions (up to 6)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))

                // Intention text fields
                VStack(spacing: 12) {
                    ForEach(intentions.indices, id: \.self) { idx in
                        IntentionInputRow(
                            index: idx,
                            text: $intentions[idx].text,
                            canRemove: intentions.count > 2,
                            onRemove: { removeIntention(at: idx) }
                        )
                    }
                }
                .frame(maxWidth: 500)

                // Add more button (if less than 6)
                if intentions.count < 6 {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            intentions.append(IntentionEntry())
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text("Add another intention")
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                // Continue button - disabled during countdown or if not enough intentions
                Button(action: {
                    saveEnteredIntentions()
                    withAnimation(.easeOut(duration: 0.3)) {
                        flowPhase = .selectingIntention
                    }
                }) {
                    Text("Continue")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(canProceedToSelection && !countdownActive ? .black : .gray)
                        .frame(width: 200, height: 50)
                        .background(canProceedToSelection && !countdownActive ? Color.white : Color.white.opacity(0.5))
                        .cornerRadius(25)
                }
                .buttonStyle(.plain)
                .disabled(!canProceedToSelection || countdownActive)
                .padding(.top, 16)
            }

            // Spacer to balance the sidebar
            if !intentionHistory.isEmpty {
                Spacer()
                    .frame(width: 220)
            }
        }
    }

    // MARK: - Intention History Sidebar

    private var intentionHistorySidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .padding(.leading, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(intentionHistory) { item in
                        Button(action: {
                            addHistoricalIntention(item.text)
                        }) {
                            HStack(spacing: 8) {
                                // Selection indicator
                                if item.timesSelected > 0 {
                                    Circle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(width: 4, height: 4)
                                } else {
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        .frame(width: 4, height: 4)
                                }

                                Text(item.text)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.35))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.white.opacity(0.001)) // Hit target
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 400)
        }
    }

    // MARK: - Phase 2: Select or Randomize Intention

    private var selectIntentionContent: some View {
        VStack(spacing: 24) {
            Text("Choose your intention")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white)

            Text("Pick one directly, or adjust weights and randomize")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))

            // Intention cards with pip weights
            VStack(spacing: 12) {
                ForEach(Array(validIntentions.enumerated()), id: \.element.id) { index, intention in
                    IntentionCard(
                        intention: intention,
                        index: findOriginalIndex(for: intention),
                        isSelected: selectedIntentionIndex == findOriginalIndex(for: intention),
                        onSelect: {
                            selectIntention(at: findOriginalIndex(for: intention))
                        },
                        onPipChange: { newPips in
                            if let origIndex = findOriginalIndex(for: intention) {
                                intentions[origIndex].pips = newPips
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: 550)

            // Randomize button
            Button(action: randomizeIntention) {
                HStack(spacing: 8) {
                    Image(systemName: "dice")
                    Text("Randomize")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.2))
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            // Back button
            Button(action: {
                withAnimation(.easeOut(duration: 0.3)) {
                    flowPhase = .enteringIntentions
                    selectedIntentionIndex = nil
                }
            }) {
                Text("← Back")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func findOriginalIndex(for intention: IntentionEntry) -> Int? {
        intentions.firstIndex(where: { $0.id == intention.id })
    }

    private func selectIntention(at index: Int?) {
        guard let index = index else { return }
        selectedIntentionIndex = index
        finalIntentionText = intentions[index].text

        // Record the selection
        DatabaseManager.shared.recordIntentionSelected(finalIntentionText)

        // Brief delay to show selection, then proceed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                flowPhase = .configuringDetails
            }
        }
    }

    private func randomizeIntention() {
        // Build weighted array
        var weightedIndices: [Int] = []
        for (index, intention) in intentions.enumerated() {
            if !intention.text.trimmingCharacters(in: .whitespaces).isEmpty {
                for _ in 0..<intention.pips {
                    weightedIndices.append(index)
                }
            }
        }

        guard !weightedIndices.isEmpty else { return }

        // Random selection with animation
        let randomIndex = weightedIndices.randomElement()!

        // Animate through a few options before landing
        animateRandomSelection(finalIndex: randomIndex)
    }

    private func animateRandomSelection(finalIndex: Int) {
        let validIndices = validIntentions.compactMap { findOriginalIndex(for: $0) }
        var currentStep = 0
        let totalSteps = 8

        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if currentStep < totalSteps {
                // Cycle through options
                selectedIntentionIndex = validIndices[currentStep % validIndices.count]
                currentStep += 1
            } else {
                timer.invalidate()
                selectIntention(at: finalIndex)
            }
        }
    }

    // MARK: - Phase 3: Configure Details

    private var configureDetailsContent: some View {
        VStack(spacing: 20) {
            Text("Your intention")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.5))

            Text("\"\(finalIntentionText)\"")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Duration selector
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
            .padding(.top, 8)

            // Apps & Sites panel
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

            // Back button
            Button(action: {
                withAnimation(.easeOut(duration: 0.3)) {
                    flowPhase = .selectingIntention
                    selectedIntentionIndex = nil
                }
            }) {
                Text("← Back")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func removeIntention(at index: Int) {
        withAnimation(.easeOut(duration: 0.2)) {
            _ = intentions.remove(at: index)
        }
    }

    private func loadIntentionHistory() {
        intentionHistory = DatabaseManager.shared.getIntentionHistory(limit: 100)
    }

    private func saveEnteredIntentions() {
        // Record all non-empty intentions to history
        for intention in intentions {
            let trimmed = intention.text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                DatabaseManager.shared.recordIntentionEntered(trimmed)
            }
        }
        // Reload history to reflect changes
        loadIntentionHistory()
    }

    private func addHistoricalIntention(_ text: String) {
        // Check if we already have this text
        let exists = intentions.contains { $0.text.trimmingCharacters(in: .whitespaces) == text }
        if exists { return }

        // Add to list if under limit
        if intentions.count < 6 {
            withAnimation(.easeOut(duration: 0.2)) {
                intentions.append(IntentionEntry(text: text, pips: 1))
            }
        } else {
            // Find first empty slot or replace last
            if let emptyIndex = intentions.firstIndex(where: { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
                intentions[emptyIndex].text = text
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
        let trimmedText = finalIntentionText.trimmingCharacters(in: .whitespaces)
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

// MARK: - Intention Input Row (for entering phase)

struct IntentionInputRow: View {
    let index: Int
    @Binding var text: String
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1).")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 24)

            TextField("", text: $text)
                .textFieldStyle(IntentionTextFieldStyle())
                .font(.system(size: 18))

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.3))
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Intention Card (for selection phase)

struct IntentionCard: View {
    let intention: IntentionEntry
    let index: Int?
    let isSelected: Bool
    let onSelect: () -> Void
    let onPipChange: (Int) -> Void

    @State private var currentPips: Int

    init(intention: IntentionEntry, index: Int?, isSelected: Bool, onSelect: @escaping () -> Void, onPipChange: @escaping (Int) -> Void) {
        self.intention = intention
        self.index = index
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onPipChange = onPipChange
        self._currentPips = State(initialValue: intention.pips)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Intention text - tappable to select
            Button(action: onSelect) {
                Text(intention.text)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            // Pip weight adjuster
            HStack(spacing: 4) {
                // Decrease button
                Button(action: {
                    if currentPips > 1 {
                        currentPips -= 1
                        onPipChange(currentPips)
                    }
                }) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 16))
                        .foregroundColor(currentPips > 1 ? .white.opacity(0.7) : .white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(currentPips <= 1)

                // Pip dots
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { pip in
                        Circle()
                            .fill(pip < currentPips ? Color.white : Color.white.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(width: 55)

                // Increase button
                Button(action: {
                    if currentPips < 5 {
                        currentPips += 1
                        onPipChange(currentPips)
                    }
                }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundColor(currentPips < 5 ? .white.opacity(0.7) : .white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(currentPips >= 5)
            }
            .padding(.trailing, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.white.opacity(0.5) : Color.clear, lineWidth: 2)
                )
        )
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Ripple State

struct RippleState: Identifiable {
    let id: UUID
    let startTime: Date
    let x: Double  // 0-1 position
    let y: Double  // 0-1 position
}

// MARK: - Ripple Background (Top-down water view - light rain effect)

struct RippleBackground: View {
    let ripples: [RippleState]
    let ambientPhase: Double
    let geometry: GeometryProxy

    var body: some View {
        ZStack {
            // Deep calm background - dark blue
            Color(red: 0.03, green: 0.05, blue: 0.12)

            // Ambient center glow
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.15, blue: 0.3).opacity(0.3),
                    Color.clear
                ]),
                center: .center,
                startRadius: 100,
                endRadius: 500
            )

            // Rain ripples
            ForEach(ripples) { ripple in
                RainRipple(ripple: ripple, geometry: geometry)
            }
        }
    }
}

// MARK: - Rain Ripple (individual raindrop ripple)

struct RainRipple: View {
    let ripple: RippleState
    let geometry: GeometryProxy

    @State private var ring1Radius: CGFloat = 0
    @State private var ring2Radius: CGFloat = 0
    @State private var ring3Radius: CGFloat = 0
    @State private var opacity1: Double = 0.25
    @State private var opacity2: Double = 0.18
    @State private var opacity3: Double = 0.12

    var body: some View {
        let centerX = geometry.size.width * ripple.x
        let centerY = geometry.size.height * ripple.y
        let maxRadius: CGFloat = 250

        ZStack {
            // Three concentric rings per ripple for more realism
            Circle()
                .stroke(Color(red: 0.3, green: 0.5, blue: 0.8).opacity(opacity1), lineWidth: 1.5)
                .frame(width: ring1Radius, height: ring1Radius)

            Circle()
                .stroke(Color(red: 0.25, green: 0.45, blue: 0.75).opacity(opacity2), lineWidth: 1)
                .frame(width: ring2Radius, height: ring2Radius)

            Circle()
                .stroke(Color(red: 0.2, green: 0.4, blue: 0.7).opacity(opacity3), lineWidth: 0.5)
                .frame(width: ring3Radius, height: ring3Radius)
        }
        .position(x: centerX, y: centerY)
        .onAppear {
            // Stagger the rings slightly
            withAnimation(.easeOut(duration: 3.0)) {
                ring1Radius = maxRadius
                opacity1 = 0
            }
            withAnimation(.easeOut(duration: 3.5).delay(0.1)) {
                ring2Radius = maxRadius * 0.85
                opacity2 = 0
            }
            withAnimation(.easeOut(duration: 4.0).delay(0.2)) {
                ring3Radius = maxRadius * 0.7
                opacity3 = 0
            }
        }
    }
}

// MARK: - Edge Progress Ring

struct EdgeProgressRing: View {
    let progress: Double
    let geometry: GeometryProxy

    var body: some View {
        let width = geometry.size.width
        let height = geometry.size.height
        let perimeter = 2 * (width + height)
        let progressLength = perimeter * progress

        Path { path in
            var remaining = progressLength

            // Top edge (left to right)
            if remaining > 0 {
                let segmentLength = min(remaining, width)
                path.move(to: CGPoint(x: 0, y: 3))
                path.addLine(to: CGPoint(x: segmentLength, y: 3))
                remaining -= segmentLength
            }

            // Right edge (top to bottom)
            if remaining > 0 {
                let segmentLength = min(remaining, height)
                path.move(to: CGPoint(x: width - 3, y: 0))
                path.addLine(to: CGPoint(x: width - 3, y: segmentLength))
                remaining -= segmentLength
            }

            // Bottom edge (right to left)
            if remaining > 0 {
                let segmentLength = min(remaining, width)
                path.move(to: CGPoint(x: width, y: height - 3))
                path.addLine(to: CGPoint(x: width - segmentLength, y: height - 3))
                remaining -= segmentLength
            }

            // Left edge (bottom to top)
            if remaining > 0 {
                let segmentLength = min(remaining, height)
                path.move(to: CGPoint(x: 3, y: height))
                path.addLine(to: CGPoint(x: 3, y: height - segmentLength))
            }
        }
        .stroke(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.3, green: 0.6, blue: 0.9).opacity(0.8),
                    Color(red: 0.4, green: 0.5, blue: 0.8).opacity(0.6),
                    Color(red: 0.5, green: 0.4, blue: 0.7).opacity(0.5)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )
        .shadow(color: Color(red: 0.3, green: 0.5, blue: 0.8).opacity(0.5), radius: 6)
    }
}
