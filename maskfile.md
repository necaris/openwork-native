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

## coverage

Run tests with SwiftPM code coverage enabled, then print app-source coverage.

```bash
set -euo pipefail

swift test --enable-code-coverage --enable-swift-testing \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -framework -Xlinker Testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib

xcrun llvm-cov report \
  .build/arm64-apple-macosx/debug/OpenWorkNativePackageTests.xctest/Contents/MacOS/OpenWorkNativePackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  -ignore-filename-regex='/.build/|/Tests/'

printf '\nCoverage JSON: '
swift test --show-codecov-path
```

## coverage-core

Run tests with SwiftPM code coverage enabled, then print coverage excluding
SwiftUI views and app entry-point code.

```bash
set -euo pipefail

swift test --enable-code-coverage --enable-swift-testing \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -framework -Xlinker Testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib

xcrun llvm-cov report \
  .build/arm64-apple-macosx/debug/OpenWorkNativePackageTests.xctest/Contents/MacOS/OpenWorkNativePackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  -ignore-filename-regex='/.build/|/Tests/|/Views/|OpenWorkNativeApp.swift'
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

## cert

Create a stable, self-signed code-signing identity for local builds, if one
does not already exist. Run this once. Signing with a stable identity (instead
of an ad-hoc signature whose hash changes every build) gives the app a stable
designated requirement, so macOS TCC permissions and Keychain ACLs survive
rebuilds.

```bash
set -euo pipefail

CERT_NAME="OpenWorkNative Local"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "${CERT_NAME}"; then
  printf 'Code-signing identity %s already present.\n' "${CERT_NAME}"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Self-signed cert with the codeSigning extended key usage.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "${WORK}/key.pem" -out "${WORK}/cert.pem" \
  -subj "/CN=${CERT_NAME}" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# -legacy is required so Apple's `security` can read the PKCS#12 MAC/cipher
# that OpenSSL 3.x would otherwise write in a newer, unreadable format.
P12_PASS="openwork-local"
openssl pkcs12 -export -legacy -out "${WORK}/identity.p12" \
  -inkey "${WORK}/key.pem" -in "${WORK}/cert.pem" -passout "pass:${P12_PASS}"

# -A authorizes any tool to use the key without a per-use prompt, which keeps
# `mask app` non-interactive. Acceptable for a local-only self-signed dev cert.
security import "${WORK}/identity.p12" -k "${KEYCHAIN}" -P "${P12_PASS}" -A \
  -T /usr/bin/codesign

printf 'Created code-signing identity %s.\n' "${CERT_NAME}"
printf 'The first `mask app` may prompt once to allow keychain access — choose Always Allow.\n'
```

## app

Build a local macOS `.app` bundle, versioned from git and signed with the local
self-signed identity (falls back to an ad-hoc signature if `mask cert` has not
been run).

```bash
set -euo pipefail

APP_NAME="OpenWorkNative"
BUNDLE_ID="com.openwork.native"
CERT_NAME="OpenWorkNative Local"
APP_DIR=".build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Version derived from git: marketing version from the latest vX.Y.Z tag (or
# 0.0.0 if untagged), build number from the commit count, plus the full
# `git describe` for traceability.
DESCRIBE="$(git describe --tags --always --dirty 2>/dev/null || echo unknown)"
BUILD_VERSION="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if printf '%s' "${TAG}" | grep -qE '^v?[0-9]+\.[0-9]+'; then
  SHORT_VERSION="$(printf '%s' "${TAG}" | sed 's/^v//')"
else
  SHORT_VERSION="0.0.0"
fi

swift build -c release

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/"

# Generate AppIcon.icns from the git-versioned master in Assets/.
ICON_SRC="Assets/AppIcon.png"
if [ -f "${ICON_SRC}" ]; then
  ICONSET=".build/AppIcon.iconset"
  rm -rf "${ICONSET}"
  mkdir -p "${ICONSET}"
  for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${ICON_SRC}" \
      --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "${double}" "${double}" "${ICON_SRC}" \
      --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "${ICONSET}" -o "${RESOURCES_DIR}/AppIcon.icns"
else
  printf 'No %s found; bundling without an app icon.\n' "${ICON_SRC}" >&2
fi

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_VERSION}</string>
    <key>GitDescribe</key>
    <string>${DESCRIBE}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
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

if security find-identity -p codesigning | grep -q "${CERT_NAME}"; then
  SIGN_ID="${CERT_NAME}"
  printf 'Signing with self-signed identity %s.\n' "${SIGN_ID}"
else
  SIGN_ID="-"
  printf 'No %s identity found; using an ad-hoc signature.\n' "${CERT_NAME}" >&2
  printf 'Run `mask cert` once for a stable identity so permissions persist.\n' >&2
fi

codesign --force --deep \
  --sign "${SIGN_ID}" \
  --entitlements ".build/entitlements.plist" \
  --identifier "${BUNDLE_ID}" \
  "${APP_DIR}"

printf 'App bundle created at %s (version %s, build %s).\n' \
  "${APP_DIR}" "${SHORT_VERSION}" "${BUILD_VERSION}"
printf 'Note: non-sandboxed build intended for local use; not notarized.\n'
```

## install

Build the `.app` bundle and install it into `~/Applications`.

```bash
set -euo pipefail

APP_NAME="OpenWorkNative"
SRC_APP=".build/${APP_NAME}.app"
DEST_DIR="${HOME}/Applications"

mask app

mkdir -p "${DEST_DIR}"
rm -rf "${DEST_DIR}/${APP_NAME}.app"
cp -R "${SRC_APP}" "${DEST_DIR}/${APP_NAME}.app"

printf 'Installed %s to %s\n' "${APP_NAME}.app" "${DEST_DIR}"
```
