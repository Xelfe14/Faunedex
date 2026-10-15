#!/bin/bash
# Brings the app on this Mac up to date in one go:
#   1. closes Xcode, which must not have the project open while it is rebuilt,
#   2. remembers your Apple Developer team, so Xcode never asks for it again,
#   3. downloads the latest code and rebuilds the Xcode project,
#   4. opens it again.
# Then in Xcode: pick your iPhone at the top of the window and press ⌘R.
#
# ./update.sh --clean also empties Xcode's build cache for the app, the fix for
# "Missing package product 'FlaunedexCore'" if it ever comes back.
set -euo pipefail
cd "$(dirname "$0")"

TEAM_FILE="Config/Team.xcconfig"
PROJECT="Flaunedex.xcodeproj/project.pbxproj"

# Replacing the project under an open Xcode leaves it with a stale view of
# the FlaunedexCore package, and the build fails with "Missing package
# product". Quitting first avoids that, and lets Xcode save the project, team
# included, before it is read below.
if pgrep -x Xcode >/dev/null; then
  echo "Fermeture d'Xcode le temps de la mise à jour…"
  osascript -e 'tell application "Xcode" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    pgrep -x Xcode >/dev/null || break
    sleep 1
  done
  if pgrep -x Xcode >/dev/null; then
    echo "✗ Xcode est toujours ouvert. Quittez-le (⌘Q), puis relancez ./update.sh." >&2
    exit 1
  fi
fi

# The team chosen in Signing & Capabilities is written into the generated
# project, which `xcodegen generate` replaces. Save it before that happens.
if [ ! -f "$TEAM_FILE" ] && [ -f "$PROJECT" ]; then
  TEAM=$(grep -o 'DEVELOPMENT_TEAM = [A-Z0-9]\{10\};' "$PROJECT" | head -n 1 | sed 's/.* = \(.*\);/\1/' || true)
  if [ -n "$TEAM" ]; then
    echo "DEVELOPMENT_TEAM = $TEAM" > "$TEAM_FILE"
    echo "✓ Équipe de signature mémorisée : $TEAM"
  fi
fi

if [ "${1:-}" = "--clean" ]; then
  rm -rf ~/Library/Developer/Xcode/DerivedData/Flaunedex-*
  echo "✓ Cache de compilation d'Xcode vidé pour Flaunedex"
fi

git pull --ff-only
xcodegen generate
open Flaunedex.xcodeproj

if [ ! -f "$TEAM_FILE" ]; then
  echo "ℹ︎ Choisissez votre équipe une fois dans Xcode (Signing & Capabilities), puis relancez ./update.sh : elle sera mémorisée."
fi
echo "✓ À jour. Dans Xcode : attendez la fin de « Resolving packages » en haut, choisissez votre iPhone, puis ⌘R."
