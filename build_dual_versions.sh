#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 Building Dual Optimized Distributions for ProjectLumina"
echo "   1. Apple Silicon M-Series (arm64)"
echo "   2. Intel Core / Xeon (x86_64)"
echo "   3. Universal 2 Fat Binary (arm64 + x86_64)"
echo "=========================================================="

EXECUTABLE_NAME="ProjectLumina"
ARM64_BUILD_DIR=".build/arm64-apple-macosx/release"
INTEL_BUILD_DIR=".build/x86_64-apple-macosx/release"

# 1. Compile arm64 (Apple Silicon)
echo ""
echo "🍏 [1/3] Compiling optimized Apple Silicon (arm64) slice..."
swift build -c release --arch arm64

# 2. Compile x86_64 (Intel)
echo ""
echo "⚡️ [2/3] Compiling optimized Intel Core / Xeon (x86_64) slice..."
swift build -c release --arch x86_64

# Function to package app bundle
package_bundle() {
    local target_bundle="$1"
    local binary_source="$2"
    local display_name="$3"
    local arch_priority="$4"
    local bundle_id="$5"
    
    echo "📦 Packaging $target_bundle..."
    rm -rf "$target_bundle"
    mkdir -p "$target_bundle/Contents/MacOS"
    mkdir -p "$target_bundle/Contents/Resources"
    
    cp "$binary_source" "$target_bundle/Contents/MacOS/$EXECUTABLE_NAME"
    if [ -f "appsettings.json" ]; then
        cp "appsettings.json" "$target_bundle/Contents/Resources/"
    fi
    
    local arch_xml=""
    if [ -n "$arch_priority" ]; then
        arch_xml="<key>LSArchitecturePriority</key><array><string>$arch_priority</string></array>"
    fi
    
    cat <<EOF > "$target_bundle/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_id</string>
    <key>CFBundleName</key>
    <string>$display_name</string>
    <key>CFBundleDisplayName</key>
    <string>$display_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    $arch_xml
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
}

# Package Standalone Apple Silicon App
package_bundle "ProjectLumina-AppleSilicon.app" "$ARM64_BUILD_DIR/$EXECUTABLE_NAME" "ProjectLumina (Apple Silicon)" "arm64" "com.shawnwang.ProjectLumina.arm64"

# Package Standalone Intel App
package_bundle "ProjectLumina-Intel.app" "$INTEL_BUILD_DIR/$EXECUTABLE_NAME" "ProjectLumina (Intel)" "x86_64" "com.shawnwang.ProjectLumina.x86_64"

# 3. Create Universal 2 Fat Binary
echo ""
echo "🌐 [3/3] Creating Universal 2 Fat Binary via lipo..."
UNIVERSAL_DIR=".build/universal-apple-macosx/release"
mkdir -p "$UNIVERSAL_DIR"
lipo -create -output "$UNIVERSAL_DIR/$EXECUTABLE_NAME" "$ARM64_BUILD_DIR/$EXECUTABLE_NAME" "$INTEL_BUILD_DIR/$EXECUTABLE_NAME"

# Package Universal App
package_bundle "ProjectLumina-Universal.app" "$UNIVERSAL_DIR/$EXECUTABLE_NAME" "ProjectLumina (Universal)" "" "com.shawnwang.ProjectLumina"

# Update default ProjectLumina.app to Universal so it launches natively on both
package_bundle "ProjectLumina.app" "$UNIVERSAL_DIR/$EXECUTABLE_NAME" "ProjectLumina" "" "com.shawnwang.ProjectLumina"

echo ""
echo "=========================================================="
echo "✅ Build & Packaging Verification Summary"
echo "=========================================================="
echo "1. Apple Silicon App: ProjectLumina-AppleSilicon.app"
lipo -info "ProjectLumina-AppleSilicon.app/Contents/MacOS/$EXECUTABLE_NAME"
ls -lh "ProjectLumina-AppleSilicon.app/Contents/MacOS/$EXECUTABLE_NAME" | awk '{print "   Size: " $5}'

echo ""
echo "2. Intel App:         ProjectLumina-Intel.app"
lipo -info "ProjectLumina-Intel.app/Contents/MacOS/$EXECUTABLE_NAME"
ls -lh "ProjectLumina-Intel.app/Contents/MacOS/$EXECUTABLE_NAME" | awk '{print "   Size: " $5}'

echo ""
echo "3. Universal App:     ProjectLumina-Universal.app"
lipo -info "ProjectLumina-Universal.app/Contents/MacOS/$EXECUTABLE_NAME"
ls -lh "ProjectLumina-Universal.app/Contents/MacOS/$EXECUTABLE_NAME" | awk '{print "   Size: " $5}'

echo ""
echo "4. Default App:       ProjectLumina.app"
lipo -info "ProjectLumina.app/Contents/MacOS/$EXECUTABLE_NAME"
ls -lh "ProjectLumina.app/Contents/MacOS/$EXECUTABLE_NAME" | awk '{print "   Size: " $5}'

echo "=========================================================="
echo "🎉 All versions packaged and verified successfully!"
