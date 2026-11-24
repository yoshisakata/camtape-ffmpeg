#!/bin/bash
# Prepares the files for a GitHub release of a build:
#   - <lib>.xcframework.zip for each framework, with the Swift Package
#     Manager checksum (swift package compute-checksum)
#   - the source tarballs from downloads/ (the Corresponding Source)
#   - checksums.txt and a Package.swift fragment for CamTape
#
#   tools/package-release.sh out/<stamp> <release-tag> <repo-url>
# Writes to release/<release-tag>/. Nothing is uploaded.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: package-release.sh out/<stamp> <tag> <repo-url>}"
TAG="${2:?release tag}"
REPO="${3:?repo url, e.g. https://github.com/<owner>/camtape-ffmpeg}"
OUT="$(cd "$OUT" && pwd)"
DEST="$ROOT/release/$TAG"
[[ -e "$DEST" ]] && { echo "$DEST exists; move it to the Trash first" >&2; exit 1; }
grep -q '^ALL PASS$' "$OUT/VERIFY.txt" || { echo "$OUT did not pass verify.sh" >&2; exit 1; }
mkdir -p "$DEST"
LIBS=(ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)

{
  echo "// Paste into packages/camtape_ffmpeg/ios/camtape_ffmpeg/Package.swift"
  echo "let ffmpegBase = \"$REPO/releases/download/$TAG\""
  echo "let ffmpegLibs: [(name: String, checksum: String)] = ["
} > "$DEST/Package.swift.fragment"
: > "$DEST/checksums.txt"
for l in "${LIBS[@]}"; do
  (cd "$OUT" && ditto -c -k --keepParent "$l.xcframework" "$DEST/$l.xcframework.zip")
  sum="$(swift package compute-checksum "$DEST/$l.xcframework.zip")"
  echo "    (\"$l\", \"$sum\")," >> "$DEST/Package.swift.fragment"
  echo "$sum  $l.xcframework.zip" >> "$DEST/checksums.txt"
done
echo "]" >> "$DEST/Package.swift.fragment"

cp "$OUT/BUILD-INFO.txt" "$OUT/VERIFY.txt" "$DEST/"
while IFS='|' read -r name file url sha; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  cp "$ROOT/downloads/$file" "$DEST/source-$file"
  echo "$sha  source-$file" >> "$DEST/checksums.txt"
done < "$ROOT/sources.lock"
echo "$DEST"
ls -la "$DEST"
