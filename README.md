# Intention OS

**Intention-first productivity for macOS**

Intention OS inverts the typical productivity tool paradigm. Rather than monitoring behavior and reporting (shame-based), it requires users to declare an intention upfront and creates friction around deviation.

## Core Loop

1. Open laptop → full-screen intention prompt appears
2. Type your intention and set a duration (default 25 min)
3. Apps and browser tabs are filtered against the intention
4. Deviating requires typing "I am choosing distraction"
5. Timer expires → full-screen prompt returns

## Design Principles

- **Friction over blocking:** We make distraction inconvenient, not impossible
- **Intention-first:** Every session starts with explicit intention-setting
- **Learning system:** The app learns which apps/URLs belong to which intentions
- **Configurable:** Core behaviors controlled via human-readable config files

## Project Structure

```
intention/
├── IntentionOS/              # macOS Swift app
│   ├── Sources/
│   │   ├── App/              # App entry point and delegate
│   │   ├── Views/            # SwiftUI views
│   │   ├── Models/           # Data models
│   │   ├── Services/         # Core services
│   │   ├── Database/         # SQLite layer
│   │   ├── Config/           # YAML config loading
│   │   └── Utils/            # Utilities
│   ├── Resources/            # Info.plist, entitlements
│   └── Package.swift         # Swift Package Manager
├── ChromeExtension/          # Chrome extension for URL filtering
└── CLAUDE.md                 # Design document
```

## Building the macOS App

```bash
cd IntentionOS
swift build
```

Or open with Xcode:
```bash
open Package.swift
```

## Installing the Chrome Extension

1. Open Chrome and go to `chrome://extensions/`
2. Enable "Developer mode"
3. Click "Load unpacked"
4. Select the `ChromeExtension` folder

## Configuration

Configuration files are stored in `~/Library/Application Support/IntentionOS/`:

- `config.yaml` - General settings (timing, appearance)
- `rules.yaml` - Always-allow/block lists
- `bundles.yaml` - App/URL bundles

## Features (Phase 1)

- [x] Full-screen intention prompt on wake/login
- [x] Multi-monitor support (prompt on all screens)
- [x] Timer with menu bar display
- [x] App filtering via Accessibility API
- [x] Explicit app/URL picker in intention UI
- [x] Bundle management (create, edit, delete, select)
- [x] Static rules from config file
- [x] Break-glass with phrase typing
- [x] Chrome extension for URL filtering
- [x] Local HTTP server for extension communication
- [x] Strict mode toggle (LLM filtering on/off)

## Permissions Required

- **Accessibility:** Monitor focused apps, window management
- **Network:** Local HTTP server for Chrome extension

## License

Copyright 2025. All rights reserved.
