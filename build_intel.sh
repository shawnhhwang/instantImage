#!/bin/bash
set -e

APP_NAME="ProjectLumina-Intel"
EXECUTABLE_NAME="ProjectLumina"
BUILD_DIR=".build/x86_64-apple-macosx/release"
APP_BUNDLE_PATH="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "⚡️ [Intel] Building release version for x86_64 (Core i5/i7/i9/Xeon)..."
swift build -c release --arch x86_64

echo "📦 [Intel] Creating App Bundle Structure at $APP_BUNDLE_PATH..."
rm -rf "$APP_BUNDLE_PATH"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "📄 [Intel] Copying x86_64 executable..."
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/"

echo "📄 [Intel] Copying Resources..."
if [ -f "appsettings.json" ]; then
    cp "appsettings.json" "$RESOURCES_DIR/"
fi

echo "📝 [Intel] Generating Info.plist..."
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.shawnwang.ProjectLumina.x86_64</string>
    <key>CFBundleName</key>
    <string>ProjectLumina (Intel)</string>
    <key>CFBundleDisplayName</key>
    <string>ProjectLumina (Intel)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSArchitecturePriority</key>
    <array>
        <string>x86_64</string>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "🔍 [Intel] Architecture Verification:"
lipo -info "$MACOS_DIR/$EXECUTABLE_NAME"
file "$MACOS_DIR/$EXECUTABLE_NAME"
echo "✨ [Intel] Done! Bundled successfully at $APP_BUNDLE_PATH"
