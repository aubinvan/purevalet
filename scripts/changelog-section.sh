#!/bin/sh
# Prints the CHANGELOG.md section of a version (without its heading), for release notes.
# Usage: ./scripts/changelog-section.sh 0.8.0
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:?usage: $0 X.Y.Z}"
awk -v v="$VERSION" '
    $0 ~ "^## \\[" v "\\]" { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' CHANGELOG.md | sed -e '/./,$!d'
