#!/usr/bin/env bash
# TestFlight release for Deep Cuts. The shared fleet script does the work: bump the
# build in project.yml, xcodegen, archive Release signed with the App Store
# Connect API key, upload, then commit and push the bump once Apple accepts it.
# Flags (--upload-only, --no-bump, --clean, --post-archive) and credentials are
# documented in ~/ios/release/testflight.sh.
cd "$(dirname "$0")/.." || exit 1
python3 scripts/validate-content.py || exit 1
# Build 22 shipped from a fresh clone without Secrets.xcconfig, so testers couldn't send suggestions.
for key in DEEPCUTS_FEEDBACK_URL DEEPCUTS_FEEDBACK_KEY; do
  grep -Eq "^$key *= *[^ ]" Config/Secrets.xcconfig 2> /dev/null || {
    echo "error: Config/Secrets.xcconfig has no $key; copy it from ~/deepcuts on the Air or ~/.tester_feedback" >&2
    exit 1
  }
done
exec "$HOME/ios/release/testflight.sh" --project DeepCuts.xcodeproj --scheme DeepCuts "$@"
