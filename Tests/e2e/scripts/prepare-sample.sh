#!/usr/bin/env bash
#
# Fetch the iOS Quickstart sample from the thunder-id/samples repository and wire it to this SDK
# checkout instead of the published release, so the E2E suite and the PR builder exercise the
# SDK source under test.
#
# The sample is copied to Tests/e2e/.quickstart and its SDK dependency is repointed there, so the
# samples checkout itself is never modified. Prints the prepared sample directory on stdout.
#
# Environment:
#   THUNDERID_SAMPLES_DIR   Existing local checkout of the samples repository to use as is
#   THUNDERID_SAMPLES_REPO  Repository to clone otherwise (default https://github.com/thunder-id/samples.git)
#   THUNDERID_SAMPLES_REF   Branch, tag, or commit to clone (default main)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$E2E_DIR/../.." && pwd)"
# The quickstart's path in the samples repository. A samples checkout from before the quickstarts
# were renamed has it at the bare platform name, so an older THUNDERID_SAMPLES_REF still works.
SAMPLE_PATHS=("quickstarts/quickstart-ios" "quickstarts/ios")
SAMPLE_DIR="$E2E_DIR/.quickstart"

if [ -n "${THUNDERID_SAMPLES_DIR:-}" ]; then
    samples_dir="$(cd "$THUNDERID_SAMPLES_DIR" && pwd)"
    echo "==> Using the samples checkout at $samples_dir" >&2
else
    samples_dir="$E2E_DIR/.samples"
    repo="${THUNDERID_SAMPLES_REPO:-https://github.com/thunder-id/samples.git}"
    ref="${THUNDERID_SAMPLES_REF:-main}"
    echo "==> Fetching $repo@$ref" >&2
    # init + fetch rather than clone --branch, so a commit SHA works as the ref too, and so a
    # re-run updates the existing shallow clone in place.
    [ -d "$samples_dir/.git" ] || git init -q "$samples_dir"
    git -C "$samples_dir" remote remove origin 2>/dev/null || true
    git -C "$samples_dir" remote add origin "$repo"
    git -C "$samples_dir" fetch -q --depth 1 origin "$ref"
    git -C "$samples_dir" checkout -q --force FETCH_HEAD
fi

SAMPLE_PATH=""
for path in "${SAMPLE_PATHS[@]}"; do
    if [ -f "$samples_dir/$path/Package.swift" ]; then SAMPLE_PATH="$path"; break; fi
done
if [ -z "$SAMPLE_PATH" ]; then
    echo "ERROR: no iOS Quickstart sample at ${SAMPLE_PATHS[*]} in $samples_dir." >&2
    exit 1
fi

echo "==> Copying $SAMPLE_PATH to $SAMPLE_DIR" >&2
# Keep .build (the build cache) and the generated Config.plist across runs.
mkdir -p "$SAMPLE_DIR"
rsync -a --delete --exclude .build --exclude Sources/Config.plist \
    "$samples_dir/$SAMPLE_PATH/" "$SAMPLE_DIR/"

echo "==> Pointing the sample at the SDK in $REPO_ROOT" >&2
# The resolved file pins the published release, which no longer applies once the dependency is
# local.
rm -f "$SAMPLE_DIR/Package.resolved"
python3 - "$SAMPLE_DIR" "$REPO_ROOT" <<'PY'
import os
import re
import sys

sample_dir, repo_root = sys.argv[1], sys.argv[2]
sdk_url = r'"https://github\.com/thunder-id/ios-sdks(?:\.git)?"'

# SwiftPM names a path dependency after its directory, so the product reference has to follow the
# checkout's directory name rather than the "ios-sdks" identity the remote URL gives it.
identity = os.path.basename(repo_root).lower()
manifest = os.path.join(sample_dir, "Package.swift")
with open(manifest) as f:
    text = f.read()
text, count = re.subn(r'\.package\(url: ' + sdk_url + r',[^)]*\)',
                      '.package(path: "%s")' % repo_root, text)
if count != 1:
    sys.exit("ERROR: no ios-sdks package dependency found in Package.swift")
text = text.replace('package: "ios-sdks"', 'package: "%s"' % identity)
with open(manifest, "w") as f:
    f.write(text)

project = os.path.join(sample_dir, "Quickstart.xcodeproj", "project.pbxproj")
with open(project) as f:
    text = f.read()
relative = os.path.relpath(repo_root, sample_dir)
text, count = re.subn(
    r'isa = XCRemoteSwiftPackageReference;\s*repositoryURL = ' + sdk_url + r';\s*requirement = \{[^}]*\};',
    'isa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = %s;' % relative, text)
if count != 1:
    sys.exit("ERROR: no ios-sdks package reference found in project.pbxproj")
text = text.replace("XCRemoteSwiftPackageReference", "XCLocalSwiftPackageReference")
with open(project, "w") as f:
    f.write(text)
PY
rm -rf "$SAMPLE_DIR/Quickstart.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"

echo "$SAMPLE_DIR"
