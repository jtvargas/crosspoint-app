#!/usr/bin/env bash
#
# CrossX App Store release helper.
#
# Archives the iOS app and uploads it to App Store Connect.
#
# Usage:
#   ./scripts/release.sh archive   # build the .xcarchive only
#   ./scripts/release.sh export    # archive + export a signed .ipa to build/export/
#   ./scripts/release.sh upload    # archive + upload directly to App Store Connect (default)
#
# Authentication (pick one):
#   1. Xcode account — be signed in to your Apple ID in Xcode
#      (Settings > Accounts). Nothing else needed; automatic signing
#      plus -allowProvisioningUpdates handles profiles.
#   2. App Store Connect API key — set all three env vars:
#        ASC_KEY_ID      (e.g. ABC123XYZ)
#        ASC_ISSUER_ID   (UUID from App Store Connect > Users and Access > Keys)
#        ASC_KEY_PATH    (path to AuthKey_ABC123XYZ.p8)
#      Recommended for CI / non-interactive use.
#
# Output lands in build/ (gitignored). After a successful upload the build
# appears in App Store Connect > TestFlight within a few minutes of processing.

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="SendToX4.xcodeproj"
SCHEME="SendToX4"
TEAM_ID="J7K9Z79S5F"
MODE="${1:-upload}"

case "$MODE" in
    archive|export|upload) ;;
    *) echo "Usage: $0 [archive|export|upload]" >&2; exit 64 ;;
esac

VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' "$PROJECT/project.pbxproj" | head -1)
BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' "$PROJECT/project.pbxproj" | head -1)
ARCHIVE_PATH="build/CrossX-${VERSION}-${BUILD}.xcarchive"
EXPORT_PATH="build/export"

# App Store Connect API key auth (optional; falls back to the Xcode account).
AUTH_ARGS=()
if [[ -n "${ASC_KEY_ID:-}" || -n "${ASC_ISSUER_ID:-}" || -n "${ASC_KEY_PATH:-}" ]]; then
    if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
        echo "error: set all of ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (or none)" >&2
        exit 64
    fi
    AUTH_ARGS=(
        -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID"
        -authenticationKeyPath "$ASC_KEY_PATH"
    )
    echo "Using App Store Connect API key $ASC_KEY_ID"
else
    echo "Using Xcode account for signing/upload (set ASC_* env vars to use an API key)"
fi

echo "==> Archiving CrossX $VERSION ($BUILD) -> $ARCHIVE_PATH"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -quiet \
    "${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}"
echo "==> Archive OK"

[[ "$MODE" == "archive" ]] && exit 0

# destination "export" writes an .ipa; "upload" sends straight to ASC.
DESTINATION="export"
[[ "$MODE" == "upload" ]] && DESTINATION="upload"

EXPORT_OPTIONS="build/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>${DESTINATION}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
PLIST
echo "</plist>" >> "$EXPORT_OPTIONS"

echo "==> Running $MODE for CrossX $VERSION ($BUILD)"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates \
    "${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}"

if [[ "$MODE" == "export" ]]; then
    echo "==> IPA written to $EXPORT_PATH/"
else
    echo "==> Uploaded CrossX $VERSION ($BUILD) to App Store Connect."
    echo "    It will appear under TestFlight once Apple finishes processing."
fi
