#!/bin/bash

# Build Intention OS as a proper macOS .app bundle

set -e

APP_NAME="Intention OS"
BUNDLE_ID="com.intention-os.IntentionOS"
VERSION="1.0.0"
BUILD_DIR="$(pwd)/.build/release"
APP_DIR="$(pwd)/build/${APP_NAME}.app"

echo "Building Intention OS..."

# Build release version
swift build -c release

echo "Creating app bundle..."

# Create app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/IntentionOS" "$APP_DIR/Contents/MacOS/"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>IntentionOS</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo ""
echo "=========================================="
echo "App bundle created at: $APP_DIR"
echo "=========================================="
echo ""
echo "To install:"
echo "1. Move the app to /Applications:"
echo "   cp -r \"$APP_DIR\" /Applications/"
echo ""
echo "2. Open the app once to trigger accessibility permission request:"
echo "   open /Applications/\"${APP_NAME}.app\""
echo ""
echo "3. Grant accessibility permission in System Preferences > Privacy & Security > Accessibility"
echo ""
echo "4. To start at login, go to:"
echo "   System Preferences > Users & Groups > Login Items"
echo "   Click '+' and add '${APP_NAME}'"
echo ""
echo "5. Or run this command to add to login items:"
echo "   osascript -e 'tell application \"System Events\" to make login item at end with properties {path:\"/Applications/${APP_NAME}.app\", hidden:false}'"
echo ""
echo "=========================================="
