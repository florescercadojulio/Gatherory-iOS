#!/usr/bin/env bash
# Checks the effective iOS deployment target for every app and test target.
# Run after changing deployment settings to catch target-specific overrides.
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_root/Gatherory.xcodeproj"
expected_target="26.0"
targets=(Gatherory GatheroryTests GatheroryUITests)
configurations=(Debug Release)
sdks=(iphoneos iphonesimulator)

for configuration in "${configurations[@]}"; do
  for sdk in "${sdks[@]}"; do
    for target in "${targets[@]}"; do
      settings_json="$(xcodebuild \
        -showBuildSettings \
        -json \
        -disableAutomaticPackageResolution \
        -project "$project" \
        -target "$target" \
        -configuration "$configuration" \
        -sdk "$sdk")"

      if ! actual_target="$(python3 -c '
import json
import sys

target, expected = sys.argv[1:]
records = json.load(sys.stdin)
matches = [record for record in records if record.get("target") == target]
if len(matches) != 1:
    raise SystemExit(f"expected one build-settings record for {target}, found {len(matches)}")
actual = matches[0].get("buildSettings", {}).get("IPHONEOS_DEPLOYMENT_TARGET")
if actual != expected:
    raise SystemExit(f"expected {target} deployment target {expected}, found {actual!r}")
print(actual)
' "$target" "$expected_target" <<<"$settings_json")"; then
        printf 'Deployment target verification failed: %s / %s / %s\n' \
          "$configuration" "$sdk" "$target" >&2
        exit 1
      fi

      printf 'Verified %s / %s / %s: iOS %s\n' \
        "$configuration" "$sdk" "$target" "$actual_target"
    done
  done
done

printf 'All app and test targets use the iOS %s deployment target.\n' "$expected_target"
