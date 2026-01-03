import SwiftUI
import AppKit

struct AppPickerView: View {
    let onSelect: (BundleApp) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var installedApps: [InstalledApp] = []

    struct InstalledApp: Identifiable {
        var id: String { bundleId }
        let bundleId: String
        let name: String
        let icon: NSImage?
        let path: String
    }

    var filteredApps: [InstalledApp] {
        if searchText.isEmpty {
            return installedApps
        }
        let query = searchText.lowercased()
        return installedApps.filter {
            $0.name.lowercased().contains(query) ||
            $0.bundleId.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select App")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()

            // Search
            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom)

            Divider()

            // App list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredApps) { app in
                        AppRowView(app: app) {
                            onSelect(BundleApp(bundleId: app.bundleId, name: app.name))
                            dismiss()
                        }
                        Divider()
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            loadInstalledApps()
        }
    }

    private func loadInstalledApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            var apps: [InstalledApp] = []

            // Search in /Applications
            let applicationDirs = [
                "/Applications",
                "/System/Applications",
                NSHomeDirectory() + "/Applications"
            ]

            for dir in applicationDirs {
                apps.append(contentsOf: findApps(in: dir))
            }

            // Sort by name
            apps.sort { $0.name.lowercased() < $1.name.lowercased() }

            DispatchQueue.main.async {
                self.installedApps = apps
            }
        }
    }

    private func findApps(in directory: String) -> [InstalledApp] {
        let fileManager = FileManager.default
        var apps: [InstalledApp] = []

        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return apps
        }

        for item in contents where item.hasSuffix(".app") {
            let appPath = (directory as NSString).appendingPathComponent(item)
            let plistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")

            guard let plist = NSDictionary(contentsOfFile: plistPath),
                  let bundleId = plist["CFBundleIdentifier"] as? String else {
                continue
            }

            let name = plist["CFBundleDisplayName"] as? String ??
                       plist["CFBundleName"] as? String ??
                       (item as NSString).deletingPathExtension

            let icon = NSWorkspace.shared.icon(forFile: appPath)

            apps.append(InstalledApp(
                bundleId: bundleId,
                name: name,
                icon: icon,
                path: appPath
            ))
        }

        return apps
    }
}

struct AppRowView: View {
    let app: AppPickerView.InstalledApp
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app")
                        .resizable()
                        .frame(width: 32, height: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.body)
                    Text(app.bundleId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .onHover { hovering in
            // Could add hover effect here
        }
    }
}

struct URLInputView: View {
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pattern: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Add URL Pattern")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("URL Pattern")
                    .font(.headline)

                TextField("e.g., github.com/myorg/*", text: $pattern)
                    .textFieldStyle(.roundedBorder)

                Text("Use * as wildcard. Examples:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("  github.com/* - All GitHub pages")
                    Text("  *.google.com/* - All Google subdomains")
                    Text("  docs.google.com/document/* - Google Docs only")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Add") {
                    let trimmed = pattern.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onAdd(trimmed)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
}
