#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TransManga"
BUNDLE_ID="com.2k3s.TransManga"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SOURCE="AppIcon.png"

echo "1. Building ${APP_NAME} in Release mode..."
swift build -c release

BIN_PATH=$(swift build -c release --show-bin-path)
EXECUTABLE_PATH="${BIN_PATH}/${APP_NAME}"

if [[ ! -f "${EXECUTABLE_PATH}" ]]; then
    echo "Error: Release binary not found at ${EXECUTABLE_PATH}"
    exit 1
fi

echo "2. Creating ${APP_BUNDLE} bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

if [[ -f "${ICON_SOURCE}" ]]; then
    echo "3. Building AppIcon.icns from ${ICON_SOURCE}..."
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "${ICONSET_DIR}"

    for SIZE in 16 32 128 256 512; do
        DOUBLE=$((SIZE * 2))
        sips -z "${SIZE}" "${SIZE}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${SIZE}x${SIZE}.png" >/dev/null
        sips -z "${DOUBLE}" "${DOUBLE}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
    done

    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
    cp "${ICON_SOURCE}" "${RESOURCES_DIR}/AppIcon.png"
    rm -rf "$(dirname "${ICONSET_DIR}")"
else
    echo "Warning: ${ICON_SOURCE} not found in $(pwd); building without custom icon."
fi

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>TransManga captures the selected manga region on your screen to detect and translate Japanese text locally.</string>
</dict>
</plist>
EOF

echo "4. Ad-hoc signing ${APP_BUNDLE}..."
codesign --force --deep --sign - "${APP_BUNDLE}"
touch "${APP_BUNDLE}"

echo "5. Done! Created ${APP_BUNDLE} in $(pwd)/${APP_BUNDLE}"
echo "   To install to /Applications, run: cp -R ${APP_BUNDLE} /Applications/"