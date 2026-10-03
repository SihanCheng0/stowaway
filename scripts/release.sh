#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/release.sh [--unsigned] [--app <path/to/Stowaway.app>]

Builds build/Stowaway-<version>.dmg, signs and notarizes it, and points the Homebrew
cask at it. Publishing is a separate step: scripts/publish.sh.

  --unsigned   Release without an Apple Developer account: ad-hoc signed, not notarized.
               Users approve the first launch once (or install with Homebrew).
  --app PATH   Package an existing Stowaway.app instead of building one.

For a quick local DMG that touches nothing else, use ./build-dmg.sh.

Environment:
  TEAM_ID         Apple Developer team ID (required unless --unsigned)
  SIGN_IDENTITY   Codesigning identity (default "Developer ID Application")
  NOTARY_PROFILE  notarytool keychain profile (default "stowaway-notary")
  TAP_DIR         Homebrew tap checkout (default ~/Projects/homebrew-tap)
  DMG_BUILDER     Styled DMG script (default ~/Projects/dmg-builder/build-dmg.sh;
                  it drives Finder, so set "none" for a plain hdiutil DMG)
EOF
}

APP_NAME="Stowaway"
TEAM_ID="${TEAM_ID:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-stowaway-notary}"
TAP_DIR="${TAP_DIR:-$HOME/Projects/homebrew-tap}"
DMG_BUILDER="${DMG_BUILDER:-$HOME/Projects/dmg-builder/build-dmg.sh}"

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo "==> $*"; }

SIGNED=1
APP=""
while [ $# -gt 0 ]; do
    case "$1" in
        --unsigned) SIGNED=0 ;;
        --app)
            [ $# -ge 2 ] || die "--app needs a path"
            [ -d "$2" ] || die "No app bundle at $2"
            APP="$(cd "$2" && pwd)"
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done
if [ -d "$TAP_DIR" ]; then
    TAP_DIR="$(cd "$TAP_DIR" && pwd)"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
cd "$ROOT"

VERSION="$(sed -n -E 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' project.yml | head -n 1)"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "Couldn't read MARKETING_VERSION from project.yml (got \"$VERSION\")"
DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
COMMIT_FILE="$BUILD_DIR/$APP_NAME-$VERSION.commit"
CASK="$TAP_DIR/Casks/stowaway.rb"

developer_id_identities() {
    security find-identity -v -p codesigning \
        | grep -F '"Developer ID Application' | grep -F "($TEAM_ID)\"" | grep -F -- "$SIGN_IDENTITY" || true
}

# Prints why the styled DMG builder can't run, or nothing if it can.
dmg_builder_problem() {
    [ "$DMG_BUILDER" != "none" ] || return 0
    if [ ! -x "$DMG_BUILDER" ]; then
        echo "No DMG builder at $DMG_BUILDER. Set DMG_BUILDER=none for a plain hdiutil DMG."
    elif ! command -v create-dmg >/dev/null; then
        echo "$DMG_BUILDER needs create-dmg: brew install create-dmg (or set DMG_BUILDER=none)."
    elif ! python3 -c 'import PIL' 2>/dev/null; then
        echo "$DMG_BUILDER needs Pillow for $(python3 --version 2>&1): python3 -m pip install --user Pillow (or set DMG_BUILDER=none)."
    fi
}

preflight() {
    step "Checking release prerequisites"
    local problems=()
    if [ -n "$(git status --porcelain)" ]; then
        problems+=("The working tree has uncommitted changes. Commit or stash them so the release matches a commit (see git status).")
    fi
    if [ ! -f "$CASK" ]; then
        problems+=("No cask at $CASK. Set TAP_DIR to your homebrew-tap checkout.")
    fi
    local builder_problem
    builder_problem="$(dmg_builder_problem)"
    if [ -n "$builder_problem" ]; then
        problems+=("$builder_problem")
    fi
    if [ "$SIGNED" = 1 ]; then
        signing_problems
    fi
    if [ ${#problems[@]} -gt 0 ]; then
        local problem
        for problem in "${problems[@]}"; do
            echo "  - $problem" >&2
        done
        die "Not ready to release."
    fi
}

# Appends to the caller's problems array.
signing_problems() {
    if [ -z "$TEAM_ID" ]; then
        problems+=("TEAM_ID isn't set. Find it under Membership details at https://developer.apple.com/account, then: export TEAM_ID=<TEAM_ID>")
    fi
    if [ -z "$(developer_id_identities)" ]; then
        problems+=("No valid \"$SIGN_IDENTITY\" identity for team ${TEAM_ID:-<TEAM_ID>} in your keychain. One-time setup: Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application (account holder only). Check with: security find-identity -v -p codesigning")
    fi
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        problems+=("Notary profile \"$NOTARY_PROFILE\" is missing or its credentials don't work. One-time setup (prompts for an app-specific password from https://account.apple.com): xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <your Apple ID> --team-id ${TEAM_ID:-<TEAM_ID>}")
    fi
}

build_app() {
    command -v xcodegen >/dev/null || die "xcodegen not found. Install it with: brew install xcodegen"
    local archive="$BUILD_DIR/$APP_NAME.xcarchive"
    local export_dir="$BUILD_DIR/export"
    local signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
    if [ "$SIGNED" = 1 ]; then
        signing=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGN_IDENTITY" "DEVELOPMENT_TEAM=$TEAM_ID" OTHER_CODE_SIGN_FLAGS=--timestamp)
    fi

    step "Generating Xcode project"
    xcodegen generate --quiet

    step "Archiving $APP_NAME $VERSION"
    rm -rf "$archive" "$export_dir"
    xcodebuild archive -quiet \
        -project "$APP_NAME.xcodeproj" \
        -scheme "$APP_NAME" \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "$archive" \
        "${signing[@]}"

    if [ "$SIGNED" = 1 ]; then
        step "Exporting with Developer ID signing"
        local options="$BUILD_DIR/ExportOptions.generated.plist"
        cp scripts/ExportOptions.plist "$options"
        plutil -replace teamID -string "$TEAM_ID" "$options"
        plutil -replace signingCertificate -string "$SIGN_IDENTITY" "$options"
        xcodebuild -exportArchive -quiet \
            -archivePath "$archive" \
            -exportPath "$export_dir" \
            -exportOptionsPlist "$options"
    else
        mkdir -p "$export_dir"
        ditto "$archive/Products/Applications/$APP_NAME.app" "$export_dir/$APP_NAME.app"
    fi
    APP="$export_dir/$APP_NAME.app"
    [ -d "$APP" ] || die "Build finished without $APP"
}

verify_app() {
    step "Verifying the app signature"
    codesign --verify --deep --strict --verbose=2 "$APP"

    local info entitlements assessment
    info="$(codesign -dvv "$APP" 2>&1)"
    grep -q '^Authority=Developer ID Application' <<<"$info" || die "$APP isn't signed with a Developer ID Application certificate."
    grep -q "^TeamIdentifier=$TEAM_ID\$" <<<"$info" || die "$APP isn't signed by team $TEAM_ID."
    grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<<"$info" || die "$APP doesn't have the hardened runtime, which notarization requires."
    grep -q '^Timestamp=' <<<"$info" || die "$APP has no secure timestamp, which notarization requires."
    entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
    if grep -q 'com.apple.security.get-task-allow' <<<"$entitlements"; then
        die "$APP has the get-task-allow (debugging) entitlement, which notarization rejects."
    fi

    # Before notarization Gatekeeper reports "Unnotarized Developer ID" and exits non-zero.
    assessment="$(spctl -a -t exec -vv "$APP" 2>&1 || true)"
    echo "$assessment"
    case "$assessment" in
        *"source=Unnotarized Developer ID"* | *"source=Notarized Developer ID"*) ;;
        *) die "Gatekeeper doesn't see a Developer ID signature on $APP." ;;
    esac
}

make_dmg() {
    rm -f "$DMG"
    mkdir -p "$BUILD_DIR"
    if [ "$DMG_BUILDER" != "none" ]; then
        step "Creating DMG with $DMG_BUILDER"
        "$DMG_BUILDER" "$APP_NAME" "$APP" "$DMG" \
            || die "$DMG_BUILDER failed. Re-run with DMG_BUILDER=none for a plain hdiutil DMG."
    else
        step "Creating DMG with hdiutil"
        local stage="$BUILD_DIR/dmg-stage"
        rm -rf "$stage"
        mkdir -p "$stage"
        ditto "$APP" "$stage/$APP_NAME.app"
        ln -s /Applications "$stage/Applications"
        hdiutil create "$DMG" -volname "$APP_NAME" -srcfolder "$stage" -format UDZO -fs HFS+ -ov -quiet
        rm -rf "$stage"
    fi
    [ -f "$DMG" ] || die "No DMG at $DMG"
}

# create-dmg drives Finder, which could leave metadata on the bundle and break its seal.
verify_dmg_contents() {
    step "Checking the app inside the DMG"
    local mount ok=1
    mount="$(mktemp -d)"
    hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$mount" "$DMG"
    codesign --verify --deep --strict "$mount/$APP_NAME.app" || ok=0
    hdiutil detach -quiet "$mount"
    rmdir "$mount" 2>/dev/null || true
    [ "$ok" = 1 ] || die "The app's signature is broken inside $DMG."
}

sign_dmg() {
    step "Signing the DMG"
    # Use the exact certificate the app was signed with; a renewed certificate keeps the
    # same name, which would make a name-based identity ambiguous.
    local certs="$BUILD_DIR/app-certificates"
    rm -rf "$certs"
    mkdir -p "$certs"
    codesign -d --extract-certificates="$certs/cert" "$APP" 2>/dev/null
    local signer
    signer="$(shasum -a 1 "$certs/cert0" | awk '{ print toupper($1) }')"
    rm -rf "$certs"
    codesign --force --timestamp --sign "$signer" "$DMG"
    codesign --verify --strict --verbose=2 "$DMG"
}

notarize_dmg() {
    step "Notarizing $(basename "$DMG") (usually a few minutes)"
    local result="$BUILD_DIR/notarization.json"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" \
        --wait --timeout 2h --output-format json >"$result" || true

    local status id
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo "unknown")"
    id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
    echo "Submission ${id:-?}: $status"
    if [ "$status" != "Accepted" ]; then
        cat "$result" >&2
        if [ -n "$id" ]; then
            echo "--- notary log ---" >&2
            xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
            echo "Status later: xcrun notarytool info $id --keychain-profile $NOTARY_PROFILE" >&2
        fi
        die "Notarization wasn't accepted."
    fi

    step "Stapling the notarization ticket"
    # The ticket can take a moment to reach Apple's CDN after "Accepted".
    local attempt
    for attempt in 1 2 3 4 5; do
        xcrun stapler staple "$DMG" && break
        [ "$attempt" -lt 5 ] || die "Notarized but stapling failed. Retry later with: xcrun stapler staple \"$DMG\" (no need to rebuild)."
        echo "Ticket not available yet; retrying in 30s."
        sleep 30
    done
    xcrun stapler validate "$DMG"

    local assessment
    assessment="$(spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 || true)"
    echo "$assessment"
    case "$assessment" in
        *"source=Notarized Developer ID"*) ;;
        *) die "Gatekeeper doesn't accept the stapled DMG." ;;
    esac
}

update_cask() {
    local sha256="$1"
    step "Updating $CASK"
    sed -i '' -E \
        -e "s/^(  version \")[^\"]*(\")$/\1$VERSION\2/" \
        -e "s/^(  sha256 \")[0-9a-f]{64}(\")$/\1$sha256\2/" \
        "$CASK"
    if ! grep -q "^  version \"$VERSION\"$" "$CASK" || ! grep -q "^  sha256 \"$sha256\"$" "$CASK"; then
        die "Couldn't set version and sha256 in $CASK. It needs lines like: sha256 \"<64 hex digits>\""
    fi
    git -C "$TAP_DIR" --no-pager diff -- Casks/stowaway.rb || true
}

preflight

if [ -z "$APP" ]; then
    build_app
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
[ "$APP_VERSION" = "$VERSION" ] || die "$APP is version $APP_VERSION, but project.yml says $VERSION."

if [ "$SIGNED" = 1 ]; then
    verify_app
fi

make_dmg
verify_dmg_contents

if [ "$SIGNED" = 1 ]; then
    sign_dmg
    notarize_dmg
fi
# publish.sh tags this commit, so the tag always matches the code in the DMG.
git rev-parse HEAD >"$COMMIT_FILE"

SHA256="$(shasum -a 256 "$DMG" | awk '{ print $1 }')"
update_cask "$SHA256"

step "Done"
echo "  DMG:     $DMG"
echo "  SHA-256: $SHA256"
if [ "$SIGNED" = 0 ]; then
    echo "  Not notarized: first launch from the DMG needs System Settings > Privacy & Security > Open Anyway."
fi
echo "Next: scripts/publish.sh (creates GitHub release v$VERSION and pushes the cask)."
