#!/bin/bash
# Brings the app on this Mac up to date in one go:
#   1. remembers your Apple Developer team, so Xcode never asks for it again,
#   2. downloads the latest code,
#   3. rebuilds the Xcode project.
# Then in Xcode: pick your iPhone at the top of the window and press ⌘R.
set -euo pipefail
cd "$(dirname "$0")"

TEAM_FILE="Config/Team.xcconfig"
PROJECT="Flaunedex.xcodeproj/project.pbxproj"

# The team chosen in Signing & Capabilities is written into the generated
# project, which `xcodegen generate` replaces. Save it before that happens.
if [ ! -f "$TEAM_FILE" ] && [ -f "$PROJECT" ]; then
  TEAM=$(grep -o 'DEVELOPMENT_TEAM = [A-Z0-9]\{10\};' "$PROJECT" | head -n 1 | sed 's/.* = \(.*\);/\1/' || true)
  if [ -n "$TEAM" ]; then
    echo "DEVELOPMENT_TEAM = $TEAM" > "$TEAM_FILE"
    echo "✓ Équipe de signature mémorisée : $TEAM"
  fi
fi

git pull --ff-only
xcodegen generate

if [ ! -f "$TEAM_FILE" ]; then
  echo "ℹ︎ Choisissez votre équipe une fois dans Xcode (Signing & Capabilities), puis relancez ./update.sh : elle sera mémorisée."
fi
echo "✓ À jour. Dans Xcode : choisissez votre iPhone en haut de la fenêtre, puis ⌘R."
