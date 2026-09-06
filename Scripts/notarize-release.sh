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
APP="${RELEASE_APP_PATH:-$DERIVED_DATA/Build/Products/Release/Kotai.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-sasu-notary}"
OUTPUT_DIR="$ROOT_DIR/.build/releases"
NOTARY_ZIP="$OUTPUT_DIR/Kotai-notary.zip"

for command in codesign python3 shasum spctl xcrun; do
  command -v "$command" >/dev/null || { echo "error: missing required command: $command" >&2; exit 1; }
done
PROJECT_VERSION="$(python3 - "$PROJECT" <<'PYTHON'
from pathlib import Path
import re
import sys

versions = re.findall(r'^\s*MARKETING_VERSION:\s*"([^"]+)"\s*$', Path(sys.argv[1]).read_text(), re.MULTILINE)
if not versions or len(set(versions)) != 1:
    raise SystemExit("error: project.yml must contain consistent MARKETING_VERSION values")
print(versions[0])
PYTHON
)"
[[ "$PROJECT_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "error: invalid MARKETING_VERSION: $PROJECT_VERSION" >&2; exit 1; }

[[ -d "$APP" ]] || "$ROOT_DIR/Scripts/build-release.sh" >/dev/null
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" == "$PROJECT_VERSION" ]] || { echo "error: app version does not match project.yml" >&2; exit 1; }
RELEASE_ZIP="$OUTPUT_DIR/Kotai-$VERSION-mac.zip"

mkdir -p "$OUTPUT_DIR"
rm -f "$NOTARY_ZIP" "$RELEASE_ZIP" "$RELEASE_ZIP.sha256"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
/usr/bin/ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"

/usr/bin/ditto --noextattr --norsrc -c -k --keepParent "$APP" "$RELEASE_ZIP"
VERIFY_DIR="$(mktemp -d "$OUTPUT_DIR/verify.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
/usr/bin/unzip -q "$RELEASE_ZIP" -d "$VERIFY_DIR"
codesign --verify --deep --strict --verbose=2 "$VERIFY_DIR/Kotai.app"
xcrun stapler validate "$VERIFY_DIR/Kotai.app"
spctl --assess --type execute --verbose=4 "$VERIFY_DIR/Kotai.app"
shasum -a 256 "$RELEASE_ZIP" > "$RELEASE_ZIP.sha256"
rm -f "$NOTARY_ZIP"
printf '%s\n' "$RELEASE_ZIP"
