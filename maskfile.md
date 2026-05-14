# OpenWork Native tasks

## build

Build the Swift package in debug mode.

```bash
swift build
```

## test

Run the Swift package test suite.

```bash
swift test --enable-swift-testing \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -framework -Xlinker Testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## lint

Run standard Swift lint tools. Requires `swiftformat` and `swiftlint` on `PATH`.

```bash
set -euo pipefail

missing=0

if command -v swiftformat >/dev/null 2>&1; then
  swiftformat --lint Package.swift Sources Tests
else
  printf 'Missing swiftformat. Install with: brew install swiftformat\n' >&2
  missing=1
fi

if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --strict
else
  printf 'Missing swiftlint. Install with: brew install swiftlint\n' >&2
  missing=1
fi

if [ "${missing}" -ne 0 ]; then
  exit 1
fi
```

## app

Build a local unsigned macOS `.app` bundle.

```bash
set -euo pipefail

APP_NAME="OpenWorkNative"
BUNDLE_ID="com.openwork.native"
APP_DIR=".build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

swift build -c release

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
EOF

cat > ".build/entitlements.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
EOF

printf 'App bundle created at %s\n' "${APP_DIR}"
printf 'Note: This is an unsigned, non-sandboxed build intended for local use.\n'
```
