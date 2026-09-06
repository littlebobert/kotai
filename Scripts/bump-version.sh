#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/project.yml"
NEW_VERSION="${1#v}"
NEW_BUILD="${2:-}"

[[ "$NEW_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
  echo "usage: ./Scripts/bump-version.sh <semantic-version> [numeric-build]" >&2
  exit 1
}
command -v python3 >/dev/null || { echo "error: python3 is required" >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "error: xcodegen is required" >&2; exit 1; }

read -r CURRENT_VERSION CURRENT_BUILD < <(python3 - "$PROJECT" <<'PYTHON'
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
[[ "$CURRENT_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
  echo "error: current version is not semantic: $CURRENT_VERSION" >&2
  exit 1
}
[[ "$CURRENT_BUILD" =~ ^(0|[1-9][0-9]*)$ ]] || {
  echo "error: current build is not numeric: $CURRENT_BUILD" >&2
  exit 1
}

VERSION_COMPARISON="$(python3 - "$NEW_VERSION" "$CURRENT_VERSION" <<'PYTHON'
import sys

new_version = tuple(map(int, sys.argv[1].split(".")))
current_version = tuple(map(int, sys.argv[2].split(".")))
print((new_version > current_version) - (new_version < current_version))
PYTHON
)"
[[ "$VERSION_COMPARISON" != -1 ]] || {
  echo "error: version must not decrease below $CURRENT_VERSION" >&2
  exit 1
}

NEW_BUILD="${NEW_BUILD:-$((10#$CURRENT_BUILD + 1))}"
[[ "$NEW_BUILD" =~ ^(0|[1-9][0-9]*)$ ]] || {
  echo "error: build must be numeric" >&2
  exit 1
}
(( 10#$NEW_BUILD > 10#$CURRENT_BUILD )) || {
  echo "error: build must increase beyond $CURRENT_BUILD" >&2
  exit 1
}

python3 - "$PROJECT" "$NEW_VERSION" "$NEW_BUILD" <<'PYTHON'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
version = sys.argv[2]
build = sys.argv[3]
text = path.read_text()
text, version_count = re.subn(
    r'(?m)^(\s*MARKETING_VERSION:\s*)"[^"]+"(\s*)$',
    rf'\g<1>"{version}"\g<2>',
    text,
)
text, build_count = re.subn(
    r'(?m)^(\s*CURRENT_PROJECT_VERSION:\s*)"[^"]+"(\s*)$',
    rf'\g<1>"{build}"\g<2>',
    text,
)
if version_count < 1 or build_count < 1:
    raise SystemExit("error: project.yml version fields were not found")
path.write_text(text)
PYTHON
xcodegen generate --spec "$PROJECT"
echo "Kotai version is now $NEW_VERSION ($NEW_BUILD)"
