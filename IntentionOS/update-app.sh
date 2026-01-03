#!/bin/bash

# Update and install Intention OS
# Usage: ./update-app.sh

set -e

APP_NAME="Intention OS"
BUNDLE_ID="com.intention-os.IntentionOS"
APP_PATH="/Applications/${APP_NAME}.app"
BUILD_PATH="$(pwd)/build/${APP_NAME}.app"

echo "=== Intention OS Updater ==="
echo ""

# 1. Kill any running instance
echo "Stopping any running instance..."
pkill -x IntentionOS 2>/dev/null || true
sleep 1

# 2. Build the app
echo "Building..."
./build-app.sh

# 3. Reset accessibility permissions for this app
echo "Resetting accessibility permissions..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

# 4. Remove old installation
echo "Removing old installation..."
rm -rf "$APP_PATH"

# 5. Install new version
echo "Installing to /Applications..."
cp -r "$BUILD_PATH" /Applications/

# 6. Add to login items (remove first to avoid duplicates, then add)
echo "Setting up login item..."
osascript -e 'tell application "System Events" to delete every login item whose name is "Intention OS"' 2>/dev/null || true
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Intention OS.app", hidden:false}'

# 7. Unfortunately, we can't grant accessibility via command line (security restriction)
# But we can open System Preferences to the right pane
echo ""
echo "=== Installation Complete ==="
echo ""
echo "Opening app and System Preferences..."
echo ""

# Open the app
open "$APP_PATH"

# Give it a moment to launch
sleep 2

# Open System Preferences to Accessibility pane
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo ""
echo "=== ACTION REQUIRED ==="
echo "1. In System Preferences, click the lock icon to make changes"
echo "2. Click '+' and add '${APP_NAME}' from /Applications"
echo "   (or toggle it off and on if it's already there)"
echo "3. Close System Preferences"
echo ""
echo "The app should now work with full permissions!"
echo "(App has been added to Login Items automatically)"
