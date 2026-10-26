#!/bin/bash
set -e

APP_NAME="ProjectLumina-AppleSilicon"
EXECUTABLE_NAME="ProjectLumina"
BUILD_DIR=".build/arm64-apple-macosx/release"
APP_BUNDLE_PATH="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🍏 [Apple Silicon] Building release version for arm64 (M1/M2/M3/M4)..."
swift build -c release --arch arm64

echo "📦 [Apple Silicon] Creating App Bundle Structure at $APP_BUNDLE_PATH..."
rm -rf "$APP_BUNDLE_PATH"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "📄 [Apple Silicon] Copying arm64 executable..."
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/"

echo "📄 [Apple Silicon] Copying Resources..."
if [ -f "appsettings.json" ]; then
    cp "appsettings.json" "$RESOURCES_DIR/"
fi

echo "📝 [Apple Silicon] Generating Info.plist..."
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.shawnwang.ProjectLumina.arm64</string>
    <key>CFBundleName</key>
    <string>ProjectLumina (Apple Silicon)</string>
    <key>CFBundleDisplayName</key>
    <string>ProjectLumina (Apple Silicon)</string>
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
        <string>arm64</string>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "🔍 [Apple Silicon] Architecture Verification:"
lipo -info "$MACOS_DIR/$EXECUTABLE_NAME"
file "$MACOS_DIR/$EXECUTABLE_NAME"
echo "✨ [Apple Silicon] Done! Bundled successfully at $APP_BUNDLE_PATH"
