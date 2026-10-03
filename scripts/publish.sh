#!/bin/bash
set -euo pipefail

# Publishes the DMG from scripts/release.sh, notarized or not. The GitHub release stays a draft,
# invisible to the in-app update check and to brew livecheck, until the cask is pushed.
# If any step fails, fix the cause and run this again; it picks up where it stopped.
#
# Usage: scripts/publish.sh
# Environment: TAP_DIR (default ~/Projects/homebrew-tap)

APP_NAME="Stowaway"
REPO="SihanCheng0/stowaway"
TAP_DIR="${TAP_DIR:-$HOME/Projects/homebrew-tap}"

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo "==> $*"; }

[ -d "$TAP_DIR" ] || die "No tap checkout at $TAP_DIR."
TAP_DIR="$(cd "$TAP_DIR" && pwd)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n -E 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' project.yml | head -n 1)"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "Couldn't read MARKETING_VERSION from project.yml (got \"$VERSION\")"
TAG="v$VERSION"
DMG="build/$APP_NAME-$VERSION.dmg"
COMMIT_FILE="build/$APP_NAME-$VERSION.commit"
CASK="$TAP_DIR/Casks/stowaway.rb"
NOTES="docs/release-notes/$TAG.md"

[ -f "$DMG" ] || die "No $DMG. Run scripts/release.sh first."
[ -f "$COMMIT_FILE" ] || die "No $COMMIT_FILE. Run scripts/release.sh first."
if xcrun stapler validate "$DMG" >/dev/null 2>&1; then
    NOTARIZED=1
else
    NOTARIZED=0
fi
COMMIT="$(cat "$COMMIT_FILE")"

SHA256="$(shasum -a 256 "$DMG" | awk '{ print $1 }')"
[ -f "$CASK" ] || die "No cask at $CASK."
if ! grep -q "^  version \"$VERSION\"$" "$CASK" || ! grep -q "^  sha256 \"$SHA256\"$" "$CASK"; then
    die "$CASK doesn't point at this DMG (version $VERSION, sha256 $SHA256). Re-run scripts/release.sh."
fi

command -v gh >/dev/null || die "gh not found. Install it with: brew install gh"
gh auth status >/dev/null 2>&1 || die "gh isn't logged in. Run: gh auth login"
gh repo view "$REPO" >/dev/null 2>&1 || die "Can't see $REPO on GitHub. Create it and push main first."
[ -n "$(git branch -r --contains "$COMMIT" 2>/dev/null)" ] \
    || die "Commit ${COMMIT:0:12}, which $DMG was built from, isn't pushed yet. Run: git push"
git -C "$TAP_DIR" ls-remote origin >/dev/null 2>&1 \
    || die "Can't reach the tap's origin. Create it with: gh repo create SihanCheng0/homebrew-tap --public, then add it as origin and push main."
[ "$(git -C "$TAP_DIR" symbolic-ref --short HEAD 2>/dev/null)" = "main" ] || die "The tap checkout isn't on main."

STATE="new"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    if [ "$(gh release view "$TAG" --repo "$REPO" --json isDraft --jq .isDraft)" = "true" ]; then
        STATE="draft"
    else
        die "$TAG is already published on $REPO."
    fi
fi

INSTALL_NOTES="## Install

\`\`\`
brew install --cask SihanCheng0/tap/stowaway
\`\`\`

Or download **$APP_NAME-$VERSION.dmg** below and drag Stowaway to Applications."
if [ "$NOTARIZED" = 0 ]; then
    INSTALL_NOTES="$INSTALL_NOTES

This build isn't notarized by Apple yet, so macOS blocks the first launch from the DMG. Open Stowaway once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. Homebrew installs open normally."
fi

if [ -f "$NOTES" ]; then
    NOTES_ARGS=(--notes-file "$NOTES")
    NOTES_SOURCE="$NOTES"
else
    # --notes is prepended to the notes GitHub generates from commits.
    NOTES_ARGS=(--notes "$INSTALL_NOTES" --generate-notes)
    NOTES_SOURCE="install instructions + generated from commits"
fi

[ -t 0 ] || die "publish.sh asks for confirmation, so run it from a terminal."
if [ "$STATE" = "new" ]; then
    FIRST_STEP="Create draft release $TAG on $REPO at commit ${COMMIT:0:12} (notes: $NOTES_SOURCE)"
else
    FIRST_STEP="Replace the DMG on the existing draft release $TAG"
fi
if [ "$NOTARIZED" = 0 ]; then
    echo "Note: $DMG is not notarized. The release notes explain the one-time Open Anyway step."
fi
cat <<EOF
About to publish $APP_NAME $VERSION:
  1. $FIRST_STEP
       asset:  $DMG
       sha256: $SHA256
  2. Commit Casks/stowaway.rb in $TAP_DIR as "stowaway $VERSION" and push it to main
  3. Publish the release and mark it Latest
EOF
read -r -p "Publish? [y/N] " answer
case "$answer" in
    y | Y | yes | YES) ;;
    *) echo "Cancelled."; exit 1 ;;
esac

if [ "$STATE" = "new" ]; then
    step "Creating draft release $TAG"
    gh release create "$TAG" "$DMG" \
        --repo "$REPO" \
        --draft \
        --title "$APP_NAME $VERSION" \
        --target "$COMMIT" \
        "${NOTES_ARGS[@]}"
else
    step "Uploading the DMG to draft release $TAG"
    gh release upload "$TAG" "$DMG" --repo "$REPO" --clobber
fi

step "Pushing the cask"
if [ -n "$(git -C "$TAP_DIR" status --porcelain -- Casks/stowaway.rb)" ]; then
    git -C "$TAP_DIR" add Casks/stowaway.rb
    git -C "$TAP_DIR" commit -m "stowaway $VERSION" -- Casks/stowaway.rb
else
    echo "Casks/stowaway.rb is already committed."
fi
git -C "$TAP_DIR" push origin HEAD:main

step "Publishing release $TAG"
gh release edit "$TAG" --repo "$REPO" --draft=false --latest

step "Published $APP_NAME $VERSION"
echo "Install: brew install --cask SihanCheng0/tap/stowaway"
echo "Update:  brew update && brew upgrade --cask stowaway"
