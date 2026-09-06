#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_ENV_FILE="${RELEASE_ENV_FILE:-$ROOT_DIR/.env.release}"
if [[ -f "$RELEASE_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$RELEASE_ENV_FILE"
  set +a
fi

PROJECT="$ROOT_DIR/project.yml"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/.build/ReleaseDerivedData}"
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Justin Henry Garcia (XDWKSAH7W3)}"
TEAM_ID="${DEVELOPMENT_TEAM:-XDWKSAH7W3}"
APP="${RELEASE_APP_PATH:-$DERIVED_DATA/Build/Products/Release/Kotai.app}"

for command in codesign lipo python3 security xcodebuild xcodegen; do
  command -v "$command" >/dev/null || { echo "error: missing required command: $command" >&2; exit 1; }
done
read -r VERSION BUILD_NUMBER < <(python3 - "$PROJECT" <<'PYTHON'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
versions = re.findall(r'^\s*MARKETING_VERSION:\s*"([^"]+)"\s*$', text, re.MULTILINE)
builds = re.findall(r'^\s*CURRENT_PROJECT_VERSION:\s*"([^"]+)"\s*$', text, re.MULTILINE)
if not versions or len(set(versions)) != 1:
    raise SystemExit("error: project.yml must contain consistent MARKETING_VERSION values")
if not builds or len(set(builds)) != 1:
    raise SystemExit("error: project.yml must contain consistent CURRENT_PROJECT_VERSION values")
print(versions[0], builds[0])
PYTHON
)
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "error: invalid MARKETING_VERSION: $VERSION" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^(0|[1-9][0-9]*)$ ]] || { echo "error: invalid CURRENT_PROJECT_VERSION: $BUILD_NUMBER" >&2; exit 1; }

SIGNING_IDENTITIES="$(security find-identity -v -p codesigning)"
grep -Fq "$IDENTITY" <<<"$SIGNING_IDENTITIES" || {
  echo "error: expected signing identity not found: $IDENTITY" >&2
  exit 1
}

cd "$ROOT_DIR"
xcodegen generate --spec "$PROJECT"
xcodebuild \
  -project Kotai.xcodeproj \
  -scheme Kotai \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  clean build

INFO_PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/Kotai"
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
[[ -d "$APP" ]] || { echo "error: release app not found: $APP" >&2; exit 1; }
[[ -x "$EXECUTABLE" ]] || { echo "error: release executable not found: $EXECUTABLE" >&2; exit 1; }
[[ -d "$SPARKLE_FRAMEWORK" ]] || { echo "error: Sparkle.framework not found: $SPARKLE_FRAMEWORK" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")" == "com.justin.Kotai" ]] || { echo "error: unexpected bundle identifier" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")" == "$VERSION" ]] || { echo "error: built version does not match project.yml" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")" == "$BUILD_NUMBER" ]] || { echo "error: built build number does not match project.yml" >&2; exit 1; }
[[ "$(lipo -archs "$EXECUTABLE")" == "arm64" ]] || { echo "error: release executable must be arm64-only" >&2; exit 1; }

codesign --force --deep --sign "$IDENTITY" --options runtime --timestamp "$SPARKLE_FRAMEWORK"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
if grep -Fq "com.apple.security.app-sandbox" <<<"$ENTITLEMENTS"; then
  echo "error: release app unexpectedly enables App Sandbox" >&2
  exit 1
fi
if grep -Fq "get-task-allow" <<<"$ENTITLEMENTS"; then
  echo "error: release app contains get-task-allow" >&2
  exit 1
fi
SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
grep -Fq "TeamIdentifier=$TEAM_ID" <<<"$SIGNATURE_DETAILS" || { echo "error: release app was not signed by team $TEAM_ID" >&2; exit 1; }
grep -Fq "Runtime Version" <<<"$SIGNATURE_DETAILS" || { echo "error: hardened runtime is not enabled" >&2; exit 1; }
FRAMEWORK_SIGNATURE="$(codesign -dv --verbose=4 "$SPARKLE_FRAMEWORK" 2>&1)"
grep -Fq "TeamIdentifier=$TEAM_ID" <<<"$FRAMEWORK_SIGNATURE" || { echo "error: Sparkle.framework was not signed by team $TEAM_ID" >&2; exit 1; }

printf '%s\n' "$APP"
