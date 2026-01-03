# Intention OS

A macOS application that inverts the typical productivity tool paradigm. Rather than monitoring behavior and reporting (shame-based), it requires you to declare an intention upfront and creates friction around deviation.

## How It Works

1. **Set an Intention** - When you open your laptop or wake from sleep, a full-screen prompt asks: "What is your intention?"
2. **Choose a Duration** - Set a timer (15, 25, 45, 60, 90 minutes, or unlimited)
3. **Select Allowed Apps/Bundles** - Choose which apps and URL patterns are allowed for this intention
4. **Focus** - Apps not aligned with your intention trigger a "break-glass" screen requiring you to type "I am choosing distraction" to proceed
5. **Repeat** - When the timer ends, set a new intention

## Requirements

- macOS 12.0 (Monterey) or later
- Swift 5.6+

## Building

### Quick Build

```bash
# Clone and enter directory
cd IntentionOS

# Build the app bundle
./build-app.sh
```

### Manual Build

```bash
# Build release version
swift build -c release

# The executable is at .build/release/IntentionOS
```

## Installation

1. **Copy to Applications:**
   ```bash
   cp -r "build/Intention OS.app" /Applications/
   ```

2. **Delete any existing database** (to get the latest default bundles):
   ```bash
   rm -f ~/Library/Application\ Support/IntentionOS/intention.db
   ```

3. **Open the app:**
   ```bash
   open "/Applications/Intention OS.app"
   ```

4. **Grant Accessibility Permission:**
   - The app will prompt you to grant accessibility access
   - Go to **System Preferences > Privacy & Security > Accessibility**
   - Enable **Intention OS**

## Start at Login

To have Intention OS start automatically when you log in:

**Option 1: Via System Preferences**
- Go to **System Preferences > Users & Groups > Login Items**
- Click the `+` button
- Select **Intention OS** from Applications

**Option 2: Via Terminal**
```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Intention OS.app", hidden:false}'
```

## Usage

### Setting an Intention

1. Type your intention (e.g., "Write design document", "Debug login issue")
2. Select a duration
3. Expand "Apps & Sites" to select:
   - **Bundles** - Pre-configured groups of apps/URLs (e.g., "Admin" allows everything)
   - **Additional Apps** - Specific apps to allow
   - **URL Patterns** - Specific URL patterns to allow (e.g., `github.com/*`)
4. Toggle "Allow LLM-approved apps/sites" for strict mode (only explicit list allowed)
5. Click **Begin**

### Default Bundles

- **Admin** - Allows ALL apps and ALL URLs (for system administration, debugging, etc.)

### Break-Glass

When you try to access an app not aligned with your intention:
- A full-screen prompt appears
- Type "I am choosing distraction" to proceed
- Optionally check "Remember" to allow this app for similar intentions in the future
- Click "Go Back" to return to your last allowed app

### Floating Timer

A small floating window in the top-right corner shows your current intention and remaining time. It's always visible and can be dragged to reposition.

### Emergency Exit

If you get stuck, **hold the Escape key for 5 seconds** to force quit the app.

## Configuration

Configuration files are stored in `~/Library/Application Support/IntentionOS/`:

- `config.yaml` - Core settings (timing, break-glass phrase, etc.)
- `rules.yaml` - Always-allowed/blocked apps and URLs
- `intention.db` - SQLite database with intentions, bundles, and history

### Example config.yaml

```yaml
default_duration_minutes: 25
warning_before_end_minutes: 5
unlimited_checkin_minutes: 30
break_glass_phrase: "I am choosing distraction"
reassert_focus_delay_ms: 100
```

### Example rules.yaml

```yaml
always_allowed:
  apps:
    - com.apple.finder
    - com.apple.Safari
  urls:
    - "*.google.com/search*"

always_blocked:
  apps: []
  urls:
    - "*.reddit.com/*"
    - "twitter.com/*"
```

## Chrome Extension (Phase 2)

A Chrome extension for URL filtering is planned. The app runs a local HTTP server on port 9999 for extension communication.

## Development

### Debug Build

```bash
swift build
.build/debug/IntentionOS
```

### Update Script (for development)

After making changes, use the update script to rebuild, reinstall, and reset permissions:

```bash
./update-app.sh
```

This script:
1. Kills any running instance
2. Rebuilds the app
3. Resets accessibility permissions
4. Installs to /Applications
5. Opens the app and System Preferences for re-granting accessibility

### Run Tests

```bash
swift test
```

## Troubleshooting

### Accessibility permission not working
1. Remove the app from the Accessibility list
2. Delete the app from /Applications
3. Rebuild with `./build-app.sh`
4. Copy fresh to /Applications
5. Re-grant permission

### Database issues
Delete the database to reset:
```bash
rm ~/Library/Application\ Support/IntentionOS/intention.db
```

## License

MIT
