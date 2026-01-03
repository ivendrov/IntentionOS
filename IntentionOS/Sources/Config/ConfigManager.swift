import Foundation

class ConfigManager {
    static let shared = ConfigManager()

    private(set) var appConfig: AppConfig = .default
    private(set) var rulesConfig: RulesConfig = .default
    private(set) var bundleConfig: BundleConfig = .default

    private let fileManager = FileManager.default
    private let yamlParser = YAMLParser()

    var configDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("IntentionOS")
    }

    var legacyConfigDirectory: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".intention-os")
    }

    private init() {}

    func loadConfig() {
        createConfigDirectoryIfNeeded()
        loadAppConfig()
        loadRulesConfig()
        loadBundleConfig()
        syncBundlesToDatabase()
    }

    private func createConfigDirectoryIfNeeded() {
        try? fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        // Also check legacy directory
        try? fileManager.createDirectory(at: legacyConfigDirectory, withIntermediateDirectories: true)
    }

    // MARK: - App Config

    private func loadAppConfig() {
        let configPath = configDirectory.appendingPathComponent("config.yaml")
        let legacyPath = legacyConfigDirectory.appendingPathComponent("config.yaml")

        let path = fileManager.fileExists(atPath: configPath.path) ? configPath :
                   (fileManager.fileExists(atPath: legacyPath.path) ? legacyPath : nil)

        guard let path = path,
              let content = try? String(contentsOf: path, encoding: .utf8) else {
            // Create default config
            createDefaultAppConfig()
            return
        }

        do {
            let parsed = try yamlParser.parse(content)
            if case .dictionary(let dict) = parsed {
                appConfig = AppConfig(
                    defaultDurationMinutes: dict["default_duration_minutes"]?.intValue ?? 25,
                    warningBeforeEndMinutes: dict["warning_before_end_minutes"]?.intValue ?? 5,
                    unlimitedCheckinMinutes: dict["unlimited_checkin_minutes"]?.intValue ?? 30,
                    breakGlassPhrase: dict["break_glass_phrase"]?.stringValue ?? "I am choosing distraction",
                    reassertFocusDelayMs: dict["reassert_focus_delay_ms"]?.intValue ?? 100,
                    llmProvider: dict["llm_provider"]?.stringValue ?? "openai",
                    llmModel: dict["llm_model"]?.stringValue ?? "gpt-4o-mini",
                    llmApiKeyEnv: dict["llm_api_key_env"]?.stringValue ?? "OPENAI_API_KEY",
                    theme: dict["theme"]?.stringValue ?? "dark",
                    backgroundAnimation: dict["background_animation"]?.stringValue ?? "orb"
                )
            }
        } catch {
            print("Failed to parse config.yaml: \(error)")
        }
    }

    private func createDefaultAppConfig() {
        let content = """
        # Timing
        default_duration_minutes: 25
        warning_before_end_minutes: 5
        unlimited_checkin_minutes: 30  # check-in interval for unlimited mode

        # Enforcement
        break_glass_phrase: "I am choosing distraction"
        reassert_focus_delay_ms: 100

        # LLM
        llm_provider: openai  # or 'anthropic'
        llm_model: gpt-4o-mini
        llm_api_key_env: OPENAI_API_KEY  # read from environment

        # Visual
        theme: dark
        background_animation: orb  # orb, faces, cityscape, none
        """

        let path = configDirectory.appendingPathComponent("config.yaml")
        try? content.write(to: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Rules Config

    private func loadRulesConfig() {
        let configPath = configDirectory.appendingPathComponent("rules.yaml")
        let legacyPath = legacyConfigDirectory.appendingPathComponent("rules.yaml")

        let path = fileManager.fileExists(atPath: configPath.path) ? configPath :
                   (fileManager.fileExists(atPath: legacyPath.path) ? legacyPath : nil)

        guard let path = path,
              let content = try? String(contentsOf: path, encoding: .utf8) else {
            createDefaultRulesConfig()
            return
        }

        do {
            let parsed = try yamlParser.parse(content)
            if case .dictionary(let dict) = parsed {
                var config = RulesConfig()

                // Parse always_allowed
                if let alwaysAllowed = dict["always_allowed"]?.dictionaryValue {
                    config.alwaysAllowed.apps = alwaysAllowed["apps"]?.arrayValue?.compactMap { $0.stringValue } ?? []
                    config.alwaysAllowed.urls = alwaysAllowed["urls"]?.arrayValue?.compactMap { $0.stringValue } ?? []
                }

                // Parse always_blocked
                if let alwaysBlocked = dict["always_blocked"]?.dictionaryValue {
                    config.alwaysBlocked.apps = alwaysBlocked["apps"]?.arrayValue?.compactMap { $0.stringValue } ?? []
                    config.alwaysBlocked.urls = alwaysBlocked["urls"]?.arrayValue?.compactMap { $0.stringValue } ?? []
                }

                // Parse intention_rules
                if let intentionRules = dict["intention_rules"]?.arrayValue {
                    config.intentionRules = intentionRules.compactMap { ruleValue -> IntentionRule? in
                        guard case .dictionary(let ruleDict) = ruleValue else { return nil }
                        return IntentionRule(
                            pattern: ruleDict["pattern"]?.stringValue ?? "",
                            allowApps: ruleDict["allow_apps"]?.arrayValue?.compactMap { $0.stringValue } ?? [],
                            allowUrls: ruleDict["allow_urls"]?.arrayValue?.compactMap { $0.stringValue } ?? []
                        )
                    }
                }

                rulesConfig = config
            }
        } catch {
            print("Failed to parse rules.yaml: \(error)")
        }
    }

    private func createDefaultRulesConfig() {
        let content = """
        # These override LLM decisions
        always_allowed:
          apps:
            - com.apple.finder
            - com.apple.Safari
            - com.google.Chrome
          urls:
            - "*.google.com/search*"

        always_blocked:
          apps: []
          urls:
            - "*.reddit.com/*"
            - "twitter.com/*"
            - "*.tiktok.com/*"

        # Intention-specific overrides (used by LLM context)
        intention_rules:
          - pattern: "code|programming|develop|debug|software"
            allow_apps:
              - com.microsoft.VSCode
              - com.apple.dt.Xcode
              - com.googlecode.iterm2
            allow_urls:
              - "github.com/*"
              - "stackoverflow.com/*"
              - "developer.apple.com/*"
        """

        let path = configDirectory.appendingPathComponent("rules.yaml")
        try? content.write(to: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Bundle Config

    private func loadBundleConfig() {
        let configPath = configDirectory.appendingPathComponent("bundles.yaml")
        let legacyPath = legacyConfigDirectory.appendingPathComponent("bundles.yaml")

        let path = fileManager.fileExists(atPath: configPath.path) ? configPath :
                   (fileManager.fileExists(atPath: legacyPath.path) ? legacyPath : nil)

        guard let path = path,
              let content = try? String(contentsOf: path, encoding: .utf8) else {
            createDefaultBundleConfig()
            return
        }

        do {
            let parsed = try yamlParser.parse(content)
            if case .dictionary(let dict) = parsed {
                if let bundlesArray = dict["bundles"]?.arrayValue {
                    bundleConfig.bundles = bundlesArray.compactMap { bundleValue -> BundleEntry? in
                        guard case .dictionary(let bundleDict) = bundleValue else { return nil }
                        guard let name = bundleDict["name"]?.stringValue else { return nil }

                        let apps = bundleDict["apps"]?.arrayValue?.compactMap { appValue -> BundleAppEntry? in
                            guard case .dictionary(let appDict) = appValue else { return nil }
                            guard let id = appDict["id"]?.stringValue,
                                  let appName = appDict["name"]?.stringValue else { return nil }
                            return BundleAppEntry(id: id, name: appName)
                        } ?? []

                        let urls = bundleDict["urls"]?.arrayValue?.compactMap { $0.stringValue } ?? []

                        return BundleEntry(name: name, apps: apps, urls: urls)
                    }
                }
            }
        } catch {
            print("Failed to parse bundles.yaml: \(error)")
        }
    }

    private func createDefaultBundleConfig() {
        let content = """
        # Bundles are saved here for easy backup/sharing
        # You can edit this file directly or use the app UI

        bundles:
          - name: Writing
            apps:
              - id: md.obsidian
                name: Obsidian
              - id: com.iawriter.mac
                name: iA Writer
            urls:
              - "nothinghuman.substack.com/publish/*"
              - "medium.com/p/*"
              - "docs.google.com/document/*"

          - name: Deep Work
            apps:
              - id: com.microsoft.VSCode
                name: VS Code
              - id: com.apple.Terminal
                name: Terminal
              - id: com.googlecode.iterm2
                name: iTerm
            urls:
              - "github.com/*"
              - "stackoverflow.com/*"
              - "*.anthropic.com/*"

          - name: Research
            apps:
              - id: com.google.Chrome
                name: Chrome
              - id: notion.id
                name: Notion
            urls:
              - "scholar.google.com/*"
              - "*.edu/*"
              - "arxiv.org/*"
              - "*.wikipedia.org/*"

          - name: Journal
            apps:
              - id: md.obsidian
                name: Obsidian
            urls: []
        """

        let path = configDirectory.appendingPathComponent("bundles.yaml")
        try? content.write(to: path, atomically: true, encoding: .utf8)
        loadBundleConfig() // Reload to parse the default
    }

    private func syncBundlesToDatabase() {
        // Sync bundles from YAML to database
        let existingBundles = DatabaseManager.shared.getAllBundles()
        let existingNames = Set(existingBundles.map { $0.name })

        for entry in bundleConfig.bundles {
            if !existingNames.contains(entry.name) {
                // Create bundle in database
                let bundle = AppBundle.create(
                    name: entry.name,
                    apps: entry.apps.map { BundleApp(bundleId: $0.id, name: $0.name) },
                    urlPatterns: entry.urls
                )
                DatabaseManager.shared.createBundle(bundle)
            }
        }
    }

    // MARK: - Save Bundle Config

    func saveBundleConfig() {
        let bundles = DatabaseManager.shared.getAllBundles()
        var yaml = "# Bundles are saved here for easy backup/sharing\n"
        yaml += "# You can edit this file directly or use the app UI\n\n"
        yaml += "bundles:\n"

        for bundle in bundles {
            yaml += "  - name: \(bundle.name)\n"
            yaml += "    apps:\n"
            for app in bundle.apps {
                yaml += "      - id: \(app.bundleId)\n"
                yaml += "        name: \(app.name)\n"
            }
            yaml += "    urls:\n"
            if bundle.urlPatterns.isEmpty {
                yaml += "      []\n"
            } else {
                for url in bundle.urlPatterns {
                    yaml += "      - \"\(url)\"\n"
                }
            }
            yaml += "\n"
        }

        let path = configDirectory.appendingPathComponent("bundles.yaml")
        try? yaml.write(to: path, atomically: true, encoding: .utf8)
    }
}
