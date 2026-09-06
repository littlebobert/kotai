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

REPO="${GITHUB_REPO:-littlebobert/kotai}"
WEBSITE_DIR="${WEBSITE_DIR:-$ROOT_DIR/../littlebobert.github.io}"
LANDING_PAGE="${LANDING_PAGE:-$WEBSITE_DIR/kotai.html}"
APPCAST_PATH="${APPCAST_PATH:-$WEBSITE_DIR/kotai-appcast.xml}"
APPCAST_PRODUCT_LINK="${APPCAST_PRODUCT_LINK:-https://kotai.jp/}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-kotai}"
TOOLS_DIR="$ROOT_DIR/.build/ReleaseDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-$TOOLS_DIR/generate_appcast}"
read -r VERSION BUILD_NUMBER < <(python3 - "$ROOT_DIR/project.yml" <<'PYTHON'
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
TAG="${RELEASE_TAG:-$VERSION}"
RELEASE_ZIP="$ROOT_DIR/.build/releases/Kotai-$VERSION-mac.zip"
CHECKSUM_FILE="$RELEASE_ZIP.sha256"
NOTES_FILE="${NOTES_FILE:-$ROOT_DIR/.build/releases/release-notes-$VERSION.md}"
APPCAST_WORK="$ROOT_DIR/.build/appcast"

for command in gh git python3 xmllint; do
  command -v "$command" >/dev/null || { echo "error: $command is required" >&2; exit 1; }
done
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "error: invalid MARKETING_VERSION: $VERSION" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^(0|[1-9][0-9]*)$ ]] || { echo "error: invalid CURRENT_PROJECT_VERSION: $BUILD_NUMBER" >&2; exit 1; }
[[ -x "$GENERATE_APPCAST" ]] || { echo "error: generate_appcast not found: $GENERATE_APPCAST" >&2; exit 1; }
[[ -f "$LANDING_PAGE" ]] || { echo "error: landing page not found: $LANDING_PAGE" >&2; exit 1; }
[[ "$(dirname "$APPCAST_PATH")" == "$WEBSITE_DIR" ]] || { echo "error: APPCAST_PATH must be in WEBSITE_DIR" >&2; exit 1; }
[[ -s "$NOTES_FILE" ]] || { echo "error: release notes not found or empty: $NOTES_FILE" >&2; exit 1; }
[[ -f "$RELEASE_ZIP" ]] || { echo "error: notarized release artifact not found: $RELEASE_ZIP" >&2; exit 1; }
[[ -f "$CHECKSUM_FILE" ]] || { echo "error: release checksum not found: $CHECKSUM_FILE" >&2; exit 1; }
gh auth status >/dev/null
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && { echo "error: release $TAG already exists" >&2; exit 1; }

rm -rf "$APPCAST_WORK"
mkdir -p "$APPCAST_WORK"
cp "$RELEASE_ZIP" "$APPCAST_WORK/"
cp "$NOTES_FILE" "$APPCAST_WORK/Kotai-$VERSION-mac.md"
[[ -f "$APPCAST_PATH" ]] && cp "$APPCAST_PATH" "$APPCAST_WORK/appcast.xml"

"$GENERATE_APPCAST" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --embed-release-notes \
  --link "$APPCAST_PRODUCT_LINK" \
  --maximum-deltas 0 \
  --versions "$BUILD_NUMBER" \
  -o "$APPCAST_WORK/appcast.xml" \
  "$APPCAST_WORK"
xmllint --noout "$APPCAST_WORK/appcast.xml"
grep -Fq "<sparkle:version>$BUILD_NUMBER</sparkle:version>" "$APPCAST_WORK/appcast.xml" || { echo "error: generated appcast is missing build $BUILD_NUMBER" >&2; exit 1; }
cp "$APPCAST_WORK/appcast.xml" "$APPCAST_PATH"

gh release create "$TAG" "$RELEASE_ZIP" "$CHECKSUM_FILE" \
  --repo "$REPO" \
  --title "Kotai $VERSION" \
  --notes-file "$APPCAST_WORK/Kotai-$VERSION-mac.md"

echo "Published GitHub release $TAG and generated $APPCAST_PATH"
echo "Commit and push kotai.html and kotai-appcast.xml from the website repository after verification."
