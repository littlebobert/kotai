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
APPCAST_PRODUCT_LINK="${APPCAST_PRODUCT_LINK:-https://littlebobert.github.io/kotai.html}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-kotai}"
PUBLIC_LANDING_URL="${PUBLIC_LANDING_URL:-https://littlebobert.github.io/kotai.html}"
PUBLIC_APPCAST_URL="${PUBLIC_APPCAST_URL:-https://littlebobert.github.io/kotai-appcast.xml}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-5.6}"
OPENAI_REASONING_EFFORT="${OPENAI_REASONING_EFFORT:-high}"
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-opus-5}"
read -r CURRENT_VERSION CURRENT_BUILD < <(python3 - "$ROOT_DIR/project.yml" <<'PYTHON'
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
VERSION_ARG=""
NOTES_FILE_ARG=""
PATCH_BUMP=false
DRY_RUN=false
NOTES=()

usage() {
  cat <<'USAGE'
Usage:
  ./Scripts/deploy-github-release.sh 0.1.0 --notes "Initial release"
  ./Scripts/deploy-github-release.sh --patch --notes-file PATH
  ./Scripts/deploy-github-release.sh --patch --dry-run --notes "Change"

An explicit version equal to project.yml's MARKETING_VERSION publishes the prepared
release and keeps CURRENT_PROJECT_VERSION. A higher explicit version increments the
build. An omitted version is equivalent to --patch; both bump the patch and build.
Dry-run validates repositories, synchronization, markers, notes, tools, appcast paths,
and release availability without changing files, building, notarizing, or publishing.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --patch)
      PATCH_BUMP=true
      ;;
    --notes)
      shift
      [[ $# -gt 0 ]] || { echo "error: --notes requires text" >&2; exit 1; }
      NOTES+=("$1")
      ;;
    --notes-file)
      shift
      [[ $# -gt 0 ]] || { echo "error: --notes-file requires a path" >&2; exit 1; }
      NOTES_FILE_ARG="$1"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      [[ -z "$VERSION_ARG" ]] || { echo "error: only one version may be supplied" >&2; exit 1; }
      VERSION_ARG="${1#v}"
      ;;
  esac
  shift
done

[[ "$PATCH_BUMP" != true || -z "$VERSION_ARG" ]] || {
  echo "error: choose either an explicit version or --patch" >&2
  exit 1
}
[[ "$CURRENT_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "error: invalid current version: $CURRENT_VERSION" >&2; exit 1; }
[[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || { echo "error: invalid current build: $CURRENT_BUILD" >&2; exit 1; }

if [[ -n "$VERSION_ARG" ]]; then
  VERSION="$VERSION_ARG"
else
  IFS='.' read -r VERSION_MAJOR VERSION_MINOR VERSION_PATCH <<<"$CURRENT_VERSION"
  VERSION="$VERSION_MAJOR.$VERSION_MINOR.$((10#$VERSION_PATCH + 1))"
fi
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "error: invalid release version: $VERSION" >&2; exit 1; }

VERSION_COMPARISON="$(python3 - "$VERSION" "$CURRENT_VERSION" <<'PY'
import sys

release = tuple(map(int, sys.argv[1].split(".")))
current = tuple(map(int, sys.argv[2].split(".")))
print((release > current) - (release < current))
PY
)"
[[ "$VERSION_COMPARISON" != -1 ]] || {
  echo "error: release version $VERSION is lower than current version $CURRENT_VERSION" >&2
  exit 1
}
if [[ -n "$VERSION_ARG" && "$VERSION_COMPARISON" == 0 ]]; then
  BUILD_NUMBER="$CURRENT_BUILD"
  METADATA_CHANGE=false
else
  BUILD_NUMBER="$((10#$CURRENT_BUILD + 1))"
  METADATA_CHANGE=true
fi
TAG="${RELEASE_TAG:-$VERSION}"
RELEASE_DIR="$ROOT_DIR/.build/releases"
RELEASE_ZIP="$RELEASE_DIR/Kotai-$VERSION-mac.zip"
CHECKSUM_FILE="$RELEASE_ZIP.sha256"
NOTES_FILE="$RELEASE_DIR/release-notes-$VERSION.md"
TRANSLATIONS_FILE="$RELEASE_DIR/release-notes-$VERSION-translations.json"
TRANSLATION_RESPONSE_FILE="$RELEASE_DIR/release-notes-$VERSION-translation-response.json"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/Kotai-$VERSION-mac.zip"

for command in codesign curl gh git python3 shasum spctl xcodebuild xcodegen xmllint xcrun; do
  command -v "$command" >/dev/null || { echo "error: missing required command: $command" >&2; exit 1; }
done
[[ -d "$WEBSITE_DIR/.git" ]] || { echo "error: website repository not found: $WEBSITE_DIR" >&2; exit 1; }
[[ -f "$LANDING_PAGE" ]] || { echo "error: landing page not found: $LANDING_PAGE" >&2; exit 1; }
[[ "$(dirname "$APPCAST_PATH")" == "$WEBSITE_DIR" ]] || { echo "error: APPCAST_PATH must be in WEBSITE_DIR" >&2; exit 1; }
[[ -z "$NOTES_FILE_ARG" || ${#NOTES[@]} -eq 0 ]] || { echo "error: use --notes or --notes-file, not both" >&2; exit 1; }
if [[ -n "$NOTES_FILE_ARG" ]]; then
  [[ -s "$NOTES_FILE_ARG" ]] || { echo "error: notes file not found or empty: $NOTES_FILE_ARG" >&2; exit 1; }
elif [[ ${#NOTES[@]} -eq 0 ]]; then
  echo "error: provide at least one --notes value or --notes-file" >&2
  exit 1
fi

python3 - "$ROOT_DIR/README.md" "$LANDING_PAGE" <<'PY'
from pathlib import Path
import sys

readme = Path(sys.argv[1]).read_text()
page = Path(sys.argv[2]).read_text()
for name, text in (("README download", readme), ("landing download", page)):
    if text.count("<!-- kotai-download:start -->") != 1 or text.count("<!-- kotai-download:end -->") != 1:
        raise SystemExit(f"error: {name} markers must occur exactly once")
if page.count("<!-- kotai-changelog:start -->") != 1 or page.count("<!-- kotai-changelog:end -->") != 1:
    raise SystemExit("error: landing changelog markers must occur exactly once")
PY

KOTAI_BRANCH="$(git -C "$ROOT_DIR" branch --show-current)"
WEBSITE_BRANCH="$(git -C "$WEBSITE_DIR" branch --show-current)"
[[ -n "$KOTAI_BRANCH" && -n "$WEBSITE_BRANCH" ]] || { echo "error: detached HEAD is not supported" >&2; exit 1; }
[[ -z "$(git -C "$ROOT_DIR" status --porcelain)" ]] || { echo "error: Kotai working tree must be clean before deployment" >&2; exit 1; }
[[ -z "$(git -C "$WEBSITE_DIR" status --porcelain)" ]] || { echo "error: website working tree must be clean before deployment" >&2; exit 1; }
git -C "$ROOT_DIR" fetch origin "$KOTAI_BRANCH"
git -C "$WEBSITE_DIR" fetch origin "$WEBSITE_BRANCH"
[[ "$(git -C "$ROOT_DIR" rev-parse HEAD)" == "$(git -C "$ROOT_DIR" rev-parse "origin/$KOTAI_BRANCH")" ]] || { echo "error: Kotai branch is not synchronized with origin" >&2; exit 1; }
[[ "$(git -C "$WEBSITE_DIR" rev-parse HEAD)" == "$(git -C "$WEBSITE_DIR" rev-parse "origin/$WEBSITE_BRANCH")" ]] || { echo "error: website branch is not synchronized with origin" >&2; exit 1; }
gh auth status >/dev/null
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && { echo "error: GitHub release $TAG already exists" >&2; exit 1; }

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run passed: $CURRENT_VERSION ($CURRENT_BUILD) -> $VERSION ($BUILD_NUMBER)"
  echo "GitHub release: $REPO tag $TAG"
  echo "Landing page: $LANDING_PAGE"
  echo "Appcast: $APPCAST_PATH"
  echo "Public landing URL: $PUBLIC_LANDING_URL"
  echo "Public appcast URL: $PUBLIC_APPCAST_URL"
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    echo "Translation provider: OpenAI $OPENAI_MODEL (Anthropic $ANTHROPIC_MODEL fallback when configured)"
  elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "Translation provider: Anthropic $ANTHROPIC_MODEL"
  else
    echo "Translation credentials are not configured; a real deployment would stop."
  fi
  exit 0
fi

[[ -n "${OPENAI_API_KEY:-}" || -n "${ANTHROPIC_API_KEY:-}" ]] || {
  echo "error: set OPENAI_API_KEY and/or ANTHROPIC_API_KEY in .env.release" >&2
  exit 1
}
mkdir -p "$RELEASE_DIR"
if [[ -n "$NOTES_FILE_ARG" ]]; then
  cp "$NOTES_FILE_ARG" "$NOTES_FILE"
else
  for NOTE in "${NOTES[@]}"; do printf -- '- %s\n' "$NOTE"; done > "$NOTES_FILE"
fi

translate_release_notes() {
  local provider="$1"
  local request_file="$RELEASE_DIR/release-notes-$VERSION-$provider-request.json"
  python3 - "$provider" "$OPENAI_MODEL" "$OPENAI_REASONING_EFFORT" "$ANTHROPIC_MODEL" "$VERSION" "$NOTES_FILE" "$request_file" <<'PY'
import json
import sys
from pathlib import Path

provider, openai_model, effort, anthropic_model, version, notes_path, request_path = sys.argv[1:8]
notes = []
for raw_line in Path(notes_path).read_text().splitlines():
    line = raw_line.strip()
    if line.startswith("- "):
        notes.append(line[2:].strip())
    elif line:
        notes.append(line)
if not notes:
    raise SystemExit("error: release notes contain no items")
prompt = f"""Translate these English release notes for Kotai {version} into natural Japanese.
Return JSON only with this exact shape:
{{"en":["same English items, unchanged"],"ja":["Japanese translations"]}}
Keep the same number and order of items. Copy every English item exactly into en.
Write complete, concise Japanese sentences without Markdown bullet markers.
English release notes:
{json.dumps(notes, ensure_ascii=False)}"""
if provider == "openai":
    body = {
        "model": openai_model,
        "input": [{"role": "user", "content": [{"type": "input_text", "text": prompt}]}],
        "reasoning": {"effort": effort},
    }
elif provider == "anthropic":
    schema = {
        "type": "object",
        "properties": {
            "en": {"type": "array", "items": {"type": "string"}},
            "ja": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["en", "ja"],
        "additionalProperties": False,
    }
    body = {
        "model": anthropic_model,
        "max_tokens": 4096,
        "messages": [{"role": "user", "content": prompt}],
        "output_config": {"format": {"type": "json_schema", "schema": schema}},
    }
else:
    raise SystemExit(f"error: unknown translation provider: {provider}")
Path(request_path).write_text(json.dumps(body))
PY

  case "$provider" in
    openai)
      echo "Translating release notes with OpenAI $OPENAI_MODEL..."
      curl -fsS https://api.openai.com/v1/responses \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d @"$request_file" > "$TRANSLATION_RESPONSE_FILE" || return 1
      ;;
    anthropic)
      echo "Translating release notes with Anthropic $ANTHROPIC_MODEL..."
      curl -fsS https://api.anthropic.com/v1/messages \
        -H "x-api-key: ${ANTHROPIC_API_KEY}" \
        -H "anthropic-version: 2023-06-01" \
        -H "Content-Type: application/json" \
        -d @"$request_file" > "$TRANSLATION_RESPONSE_FILE" || return 1
      ;;
  esac
  rm -f "$request_file"

  python3 - "$provider" "$TRANSLATION_RESPONSE_FILE" "$NOTES_FILE" "$TRANSLATIONS_FILE" <<'PY'
import json
import sys
from pathlib import Path

provider, response_path, notes_path, output_path = sys.argv[1:5]
data = json.loads(Path(response_path).read_text())
if provider == "openai":
    text = (data.get("output_text") or "").strip()
    if not text:
        text = "\n".join(
            part.get("text", "")
            for item in data.get("output", [])
            for part in item.get("content", [])
            if part.get("text")
        ).strip()
else:
    text = "\n".join(
        part.get("text", "")
        for part in data.get("content", [])
        if part.get("type") == "text" and part.get("text")
    ).strip()
if text.startswith("```"):
    lines = text.splitlines()
    text = "\n".join(lines[1:-1] if lines[-1].startswith("```") else lines[1:]).strip()
translated = json.loads(text)
english = translated.get("en") or []
japanese = translated.get("ja") or []
source = []
for raw_line in Path(notes_path).read_text().splitlines():
    line = raw_line.strip()
    if line.startswith("- "):
        source.append(line[2:].strip())
    elif line:
        source.append(line)
if english != source:
    raise SystemExit(f"error: {provider} did not preserve the English release notes")
if not japanese or len(english) != len(japanese):
    raise SystemExit(f"error: {provider} returned mismatched bilingual notes")
Path(output_path).write_text(json.dumps({"en": english, "ja": japanese}, ensure_ascii=False))
PY
  rm -f "$TRANSLATION_RESPONSE_FILE"
}

TRANSLATED=false
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  if translate_release_notes openai; then
    TRANSLATED=true
  else
    echo "warning: OpenAI translation failed" >&2
    rm -f "$TRANSLATION_RESPONSE_FILE"
  fi
fi
if [[ "$TRANSLATED" != true && -n "${ANTHROPIC_API_KEY:-}" ]]; then
  translate_release_notes anthropic || { echo "error: Anthropic translation failed" >&2; exit 1; }
  TRANSLATED=true
fi
[[ "$TRANSLATED" == true ]] || { echo "error: no translation provider succeeded" >&2; exit 1; }

if [[ "$METADATA_CHANGE" == true ]]; then
  "$ROOT_DIR/Scripts/bump-version.sh" "$VERSION" "$BUILD_NUMBER"
fi
python3 - "$ROOT_DIR/README.md" "$LANDING_PAGE" "$VERSION" "$DOWNLOAD_URL" "$TRANSLATIONS_FILE" "$METADATA_CHANGE" <<'PY'
from pathlib import Path
import datetime
import html
import json
import re
import sys

readme_path, page_path = map(Path, sys.argv[1:3])
version, download_url = sys.argv[3:5]
translations = json.loads(Path(sys.argv[5]).read_text())
metadata_change = sys.argv[6] == "true"

def replace_marker_block(text: str, marker_name: str, content: str) -> str:
    pattern = re.compile(
        rf"<!-- {re.escape(marker_name)}:start -->.*?<!-- {re.escape(marker_name)}:end -->",
        re.DOTALL,
    )
    replacement = f"<!-- {marker_name}:start -->\n{content}\n<!-- {marker_name}:end -->"
    updated, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise SystemExit(f"error: {marker_name} markers were not found exactly once")
    return updated

readme = readme_path.read_text()
readme_download = f"[Download Kotai {version} for Apple Silicon]({download_url})"
readme_path.write_text(replace_marker_block(readme, "kotai-download", readme_download))

page = page_path.read_text()
page_download = (
    f'<a class="download-link" href="{html.escape(download_url, quote=True)}" '
    'data-label-en="Download for macOS" data-label-ja="macOS版をダウンロード">Download for macOS</a>\n'
    f'<span class="download-version" data-label-en="(version {version})" '
    f'data-label-ja="（バージョン {version}）">(version {version})</span>'
)
page = replace_marker_block(page, "kotai-download", page_download)
changelog_start = "<!-- kotai-changelog:start -->"
changelog_end = "<!-- kotai-changelog:end -->"
start_index = page.index(changelog_start) + len(changelog_start)
end_index = page.index(changelog_end, start_index)
existing_changelog = page[start_index:end_index]
version_entry_exists = re.search(
    rf"<h2>\s*{re.escape(version)}\s*</h2>",
    existing_changelog,
)
if version_entry_exists and metadata_change:
    raise SystemExit(f"error: changelog already contains version {version}")
if version_entry_exists:
    page_path.write_text(page)
    raise SystemExit(0)
today = datetime.date.today()
english_months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
date_en = f"{english_months[today.month - 1]} {today.day}, {today.year}"
date_ja = f"{today.year}年{today.month}月{today.day}日"
items = "\n".join(
    f'  <li data-label-en="{html.escape(english, quote=True)}" data-label-ja="{html.escape(japanese, quote=True)}">{html.escape(english)}</li>'
    for english, japanese in zip(translations["en"], translations["ja"])
)
entry = (
    f"\n<h2>{html.escape(version)}</h2>\n"
    f'<span class="release-date" data-label-en="{date_en}" data-label-ja="{date_ja}">{date_en}</span>\n'
    f"<ul>\n{items}\n</ul>\n"
)
page = page[:start_index] + entry + existing_changelog + page[end_index:]
page_path.write_text(page)
PY

xcodegen generate --spec "$ROOT_DIR/project.yml"
TEST_DERIVED_DATA="$ROOT_DIR/.build/DeployTests"
rm -rf "$TEST_DERIVED_DATA"
xcodebuild \
  -project "$ROOT_DIR/Kotai.xcodeproj" \
  -scheme Kotai \
  -configuration Debug \
  -derivedDataPath "$TEST_DERIVED_DATA" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
python3 - "$ROOT_DIR" <<'PYTHON'
import os
import signal
import subprocess
import sys

root = sys.argv[1]
command = [
    "xcodebuild",
    "-project", f"{root}/Kotai.xcodeproj",
    "-scheme", "Kotai",
    "-configuration", "Debug",
    "-derivedDataPath", f"{root}/.build/DeployTests",
    "-destination", "platform=macOS,arch=arm64",
    "CODE_SIGNING_ALLOWED=NO",
    "test-without-building",
]
process = subprocess.Popen(command, start_new_session=True)
try:
    result = process.wait(timeout=120)
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
    raise SystemExit("error: tests exceeded the two-minute safety timeout")
if result != 0:
    raise SystemExit(result)
PYTHON
"$ROOT_DIR/Scripts/build-release.sh"
"$ROOT_DIR/Scripts/notarize-release.sh"
APP="${RELEASE_APP_PATH:-$ROOT_DIR/.build/ReleaseDerivedData/Build/Products/Release/Kotai.app}"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]] || { echo "error: built version mismatch" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD_NUMBER" ]] || { echo "error: built build number mismatch" >&2; exit 1; }
[[ -f "$RELEASE_ZIP" && -f "$CHECKSUM_FILE" ]] || { echo "error: release artifact missing" >&2; exit 1; }

SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-$ROOT_DIR/.build/ReleaseDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast}"
[[ -x "$SPARKLE_GENERATE_APPCAST" ]] || { echo "error: generate_appcast not found: $SPARKLE_GENERATE_APPCAST" >&2; exit 1; }
APPCAST_WORK="$ROOT_DIR/.build/appcast"
rm -rf "$APPCAST_WORK"
mkdir -p "$APPCAST_WORK"
cp "$RELEASE_ZIP" "$APPCAST_WORK/"
cp "$NOTES_FILE" "$APPCAST_WORK/Kotai-$VERSION-mac.md"
[[ -f "$APPCAST_PATH" ]] && cp "$APPCAST_PATH" "$APPCAST_WORK/appcast.xml"
"$SPARKLE_GENERATE_APPCAST" \
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
grep -Fq "https://github.com/$REPO/releases/download/$TAG/" "$APPCAST_WORK/appcast.xml" || { echo "error: generated appcast has an unexpected download prefix" >&2; exit 1; }
cp "$APPCAST_WORK/appcast.xml" "$APPCAST_PATH"

rm -f "$TRANSLATIONS_FILE" "$TRANSLATION_RESPONSE_FILE"
git -C "$ROOT_DIR" add -- project.yml Kotai.xcodeproj README.md
if git -C "$ROOT_DIR" diff --cached --quiet; then
  echo "Kotai release metadata and documentation are unchanged; reusing $KOTAI_BRANCH at $(git -C "$ROOT_DIR" rev-parse --short HEAD)."
else
  git -C "$ROOT_DIR" commit -m "Release Kotai $VERSION"
  git -C "$ROOT_DIR" push origin "$KOTAI_BRANCH"
fi
gh release create "$TAG" "$RELEASE_ZIP" "$CHECKSUM_FILE" \
  --repo "$REPO" --target "$KOTAI_BRANCH" --title "Kotai $VERSION" --notes-file "$APPCAST_WORK/Kotai-$VERSION-mac.md"
LANDING_RELATIVE="${LANDING_PAGE#"$WEBSITE_DIR"/}"
APPCAST_RELATIVE="${APPCAST_PATH#"$WEBSITE_DIR"/}"
git -C "$WEBSITE_DIR" add -- "$LANDING_RELATIVE" "$APPCAST_RELATIVE"
if git -C "$WEBSITE_DIR" diff --cached --quiet; then
  echo "Website landing page is unchanged; reusing $WEBSITE_BRANCH at $(git -C "$WEBSITE_DIR" rev-parse --short HEAD)."
else
  git -C "$WEBSITE_DIR" commit -m "Publish Kotai $VERSION"
  git -C "$WEBSITE_DIR" push origin "$WEBSITE_BRANCH"
fi

VERIFY_DIR="$(mktemp -d /tmp/kotai-release.XXXXXX)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
curl -fL "$DOWNLOAD_URL" -o "$VERIFY_DIR/Kotai-$VERSION-mac.zip"
EXPECTED_CHECKSUM="$(cut -d' ' -f1 "$CHECKSUM_FILE")"
ACTUAL_CHECKSUM="$(shasum -a 256 "$VERIFY_DIR/Kotai-$VERSION-mac.zip" | cut -d' ' -f1)"
[[ "$EXPECTED_CHECKSUM" == "$ACTUAL_CHECKSUM" ]] || { echo "error: public checksum mismatch" >&2; exit 1; }
/usr/bin/unzip -q "$VERIFY_DIR/Kotai-$VERSION-mac.zip" -d "$VERIFY_DIR/extracted"
codesign --verify --deep --strict --verbose=2 "$VERIFY_DIR/extracted/Kotai.app"
xcrun stapler validate "$VERIFY_DIR/extracted/Kotai.app"
spctl --assess --type execute --verbose=4 "$VERIFY_DIR/extracted/Kotai.app"

for ATTEMPT in {1..24}; do
  if curl -fL "$PUBLIC_APPCAST_URL" -o "$VERIFY_DIR/appcast.xml" 2>/dev/null \
      && curl -fL "$PUBLIC_LANDING_URL" -o "$VERIFY_DIR/landing.html" 2>/dev/null \
      && xmllint --noout "$VERIFY_DIR/appcast.xml" \
      && grep -Fq "<sparkle:version>$BUILD_NUMBER</sparkle:version>" "$VERIFY_DIR/appcast.xml" \
      && grep -Fq "$DOWNLOAD_URL" "$VERIFY_DIR/appcast.xml" \
      && grep -Fq "$DOWNLOAD_URL" "$VERIFY_DIR/landing.html" \
      && grep -Fq ">$VERSION</h2>" "$VERIFY_DIR/landing.html"; then
    echo "Published and verified Kotai $VERSION ($BUILD_NUMBER)"
    echo "https://github.com/$REPO/releases/tag/$TAG"
    exit 0
  fi
  sleep 10
done

echo "error: release is published, but the public website/feed did not verify within four minutes" >&2
exit 1
