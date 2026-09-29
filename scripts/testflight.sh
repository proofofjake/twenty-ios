#!/bin/zsh
# Archive a Release build and upload it to App Store Connect / TestFlight.
#
#   scripts/testflight.sh            # archive + upload
#   scripts/testflight.sh --no-upload  # archive + export an .ipa only (dry run)
#
# Upload auth: the Apple ID signed into Xcode (Settings → Accounts), or an
# App Store Connect API key via ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID.
# Needs a paid Apple Developer Program team in project.yml (DEVELOPMENT_TEAM).
set -euo pipefail
cd "$(dirname "$0")/.."

UPLOAD=1
[[ "${1:-}" == "--no-upload" ]] && UPLOAD=0

TEAM=$(grep -m1 'DEVELOPMENT_TEAM' project.yml | sed -E 's/.*"([A-Z0-9]+)".*/\1/')
BUILD=$(date -u +%Y%m%d%H%M)   # always increasing, as App Store Connect requires
OUT=build-release
ARCHIVE=$OUT/TwentyCRM-$BUILD.xcarchive

AUTH=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

xcodegen generate >/dev/null
echo "▸ Archiving build $BUILD (team $TEAM)"
xcodebuild -project TwentyCRM.xcodeproj -scheme TwentyCRM -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates "${AUTH[@]}" \
  CURRENT_PROJECT_VERSION="$BUILD" archive | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"

DESTINATION=upload
[[ $UPLOAD == 0 ]] && DESTINATION=export
cat > $OUT/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DESTINATION</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST

echo "▸ Exporting (${DESTINATION})"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export-$BUILD" \
  -exportOptionsPlist $OUT/ExportOptions.plist -allowProvisioningUpdates "${AUTH[@]}" \
  | grep -E "error:|EXPORT (SUCCEEDED|FAILED)|Upload"

if [[ $UPLOAD == 1 ]]; then
  echo "✓ Uploaded build $BUILD. It appears in TestFlight after processing (usually 5–15 min)."
else
  echo "✓ Exported to $OUT/export-$BUILD (not uploaded)."
fi
