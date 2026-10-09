#!/usr/bin/env bash
# Prints the GitHub release body for a version: the one-line headline from
# CHANGELOG.md plus a link to the full entry. The detailed bullet lists stay in
# CHANGELOG.md only, so the release page and README never duplicate them.
#
# Usage: tool/release_notes.sh v0.1.2
set -euo pipefail

tag="${1:?usage: release_notes.sh <tag, e.g. v0.1.2>}"
version="${tag#v}"
cd "$(dirname "$0")/.."

# First non-empty line under "## <version>" that is not a heading or bullet.
headline="$(awk -v v="$version" '
  $0 ~ "^## " v "( |$)" { found = 1; next }
  found && /^## /       { exit }
  found && NF && !/^(#|-)/ { print; exit }
' CHANGELOG.md)"

if [ -z "$headline" ]; then
  echo "No CHANGELOG.md entry with a headline for $version" >&2
  exit 1
fi

printf '%s\n\n' "$headline"
printf '完整更新日志 / Full changelog: https://github.com/%s/blob/%s/CHANGELOG.md\n' \
  "${GITHUB_REPOSITORY:-stmtc233/rawviewer}" "$tag"
