#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUNDLE_ID="com.justin.Kotai"
DERIVED_DATA="$ROOT/.build/DerivedData"
IDENTITY="Developer ID Application: Justin Henry Garcia (XDWKSAH7W3)"
SHOULD_CLEAN=1

if [[ "${1:-}" == "--no-clean" ]]; then
  SHOULD_CLEAN=0
elif [[ $# -gt 0 ]]; then
  print -u2 "Usage: $0 [--no-clean]"
  exit 64
fi

for command in xcodegen xcodebuild codesign; do
  command -v "$command" >/dev/null || {
    print -u2 "error: $command is required"
    exit 1
  }
done

cd "$ROOT"
/usr/bin/pkill -x Kotai 2>/dev/null || true
xcodegen generate --quiet

if (( SHOULD_CLEAN )); then
  /bin/rm -rf "$DERIVED_DATA"
fi

/usr/bin/xcodebuild \
  -project Kotai.xcodeproj \
  -scheme Kotai \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM=XDWKSAH7W3 \
  ENABLE_HARDENED_RUNTIME=YES \
  build

APP="$DERIVED_DATA/Build/Products/Debug/Kotai.app"
INFO_PLIST="$APP/Contents/Info.plist"

[[ -d "$APP" ]] || { print -u2 "error: app bundle not found at $APP"; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")" == "$BUNDLE_ID" ]]
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/codesign -dv --verbose=2 "$APP" 2>&1 | /usr/bin/grep -F "Authority=$IDENTITY" >/dev/null
/usr/bin/open "$APP"
print "Launched $APP"
