import SwiftUI

struct BundleManagerView: View {
    @EnvironmentObject var viewModel: IntentionPromptViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var bundles: [AppBundle] = []
    @State private var editingBundle: AppBundle?
    @State private var showNewBundleSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Bundles")
                    .font(.title2.bold())
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Bundle list
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(bundles) { bundle in
                        BundleRowView(bundle: bundle) {
                            editingBundle = bundle
                        } onDelete: {
                            deleteBundle(bundle)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Add new bundle button
            Button(action: { showNewBundleSheet = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create New Bundle")
                }
            }
            .buttonStyle(.borderless)
            .padding()
        }
        .frame(width: 500, height: 400)
        .onAppear {
            loadBundles()
        }
        .sheet(item: $editingBundle) { bundle in
            BundleEditorView(bundle: bundle) { updatedBundle in
                DatabaseManager.shared.updateBundle(updatedBundle)
                loadBundles()
                viewModel.loadBundles()
            }
        }
        .sheet(isPresented: $showNewBundleSheet) {
            BundleEditorView(bundle: nil) { newBundle in
                DatabaseManager.shared.createBundle(newBundle)
                loadBundles()
                viewModel.loadBundles()
            }
        }
    }

    private func loadBundles() {
        bundles = DatabaseManager.shared.getAllBundles()
    }

    private func deleteBundle(_ bundle: AppBundle) {
        DatabaseManager.shared.deleteBundle(id: bundle.id)
        loadBundles()
        viewModel.loadBundles()
    }
}

struct BundleRowView: View {
    let bundle: AppBundle
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(bundle.name)
                    .font(.headline)

                Text(bundleSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Edit") {
                onEdit()
            }
            .buttonStyle(.bordered)

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    var bundleSummary: String {
        var parts: [String] = []
        if !bundle.apps.isEmpty {
            parts.append(bundle.apps.map { $0.name }.joined(separator: ", "))
        }
        if !bundle.urlPatterns.isEmpty {
            parts.append(bundle.urlPatterns.prefix(2).joined(separator: ", "))
            if bundle.urlPatterns.count > 2 {
                parts.append("...")
            }
        }
        return parts.joined(separator: " | ")
    }
}

struct BundleEditorView: View {
    let bundle: AppBundle?
    let onSave: (AppBundle) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var apps: [BundleApp] = []
    @State private var urlPatterns: [String] = []
    @State private var showAppPicker = false
    @State private var newURLPattern: String = ""

    var isEditing: Bool { bundle != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Bundle" : "New Bundle")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        TextField("Bundle name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Apps
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Apps")
                                .font(.headline)
                            Spacer()
                            Button("Add App") {
                                showAppPicker = true
                            }
                            .buttonStyle(.borderless)
                        }

                        if apps.isEmpty {
                            Text("No apps added")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(apps) { app in
                                HStack {
                                    Text(app.name)
                                    Spacer()
                                    Text(app.bundleId)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Button(action: {
                                        apps.removeAll { $0.bundleId == app.bundleId }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    // URLs
                    VStack(alignment: .leading, spacing: 8) {
                        Text("URL Patterns")
                            .font(.headline)

                        HStack {
                            TextField("e.g., github.com/*", text: $newURLPattern)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                if !newURLPattern.isEmpty {
                                    urlPatterns.append(newURLPattern)
                                    newURLPattern = ""
                                }
                            }
                            .disabled(newURLPattern.isEmpty)
                        }

                        if urlPatterns.isEmpty {
                            Text("No URL patterns added")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(urlPatterns, id: \.self) { pattern in
                                HStack {
                                    Text(pattern)
                                    Spacer()
                                    Button(action: {
                                        urlPatterns.removeAll { $0 == pattern }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Save button
            HStack {
                Spacer()
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
        .onAppear {
            if let bundle = bundle {
                name = bundle.name
                apps = bundle.apps
                urlPatterns = bundle.urlPatterns
            }
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView { app in
                if !apps.contains(where: { $0.bundleId == app.bundleId }) {
                    apps.append(app)
                }
            }
        }
    }

    private func save() {
        let now = Date()
        let bundleToSave = AppBundle(
            id: bundle?.id ?? 0,
            name: name.trimmingCharacters(in: .whitespaces),
            apps: apps,
            urlPatterns: urlPatterns,
            allowAllApps: bundle?.allowAllApps ?? false,
            allowAllURLs: bundle?.allowAllURLs ?? false,
            createdAt: bundle?.createdAt ?? now,
            updatedAt: now
        )
        onSave(bundleToSave)
        ConfigManager.shared.saveBundleConfig()
        dismiss()
    }
}
