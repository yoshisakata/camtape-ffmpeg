#!/bin/bash
# Prepares the files for a GitHub release of a build:
#   - <lib>.xcframework.zip for each framework, with the Swift Package
#     Manager checksum (swift package compute-checksum)
#   - the source tarballs from downloads/ (the Corresponding Source)
#   - the licence texts and NOTICE.txt (license-*, taken from the sources)
#   - checksums.txt and a Package.swift fragment for CamTape
#
#   tools/package-release.sh out/<stamp> <release-tag> <repo-url>
# Writes to release/<release-tag>/. Nothing is uploaded.
#
# A published zip must never be replaced: CamTape's Package.swift pins its
# checksum. To change a build, make a new release with a new tag.
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

# Plain, reproducible zips: entries in sorted order, no extra fields (-X:
# no access times, uid/gid or Mac metadata such as AppleDouble "._*"
# entries for com.apple.provenance). Only names, contents and modification
# times go in, so the same build always gives the same zip and checksum.
# (ditto -c -k stores the access time, which changes whenever a file is read.)
zip_xcf() {
  (cd "$OUT" && find "$1.xcframework" -print | LC_ALL=C sort \
    | TZ=UTC zip -q -X -y -D -@ "$2")
}

{
  echo "// Paste into packages/camtape_ffmpeg/ios/camtape_ffmpeg/Package.swift"
  echo "let ffmpegRelease = \"$REPO/releases/download/$TAG\""
  echo "let ffmpegLibs: [(name: String, checksum: String)] = ["
} > "$DEST/Package.swift.fragment"
: > "$DEST/checksums.txt"
for l in "${LIBS[@]}"; do
  zip_xcf "$l" "$DEST/$l.xcframework.zip"
  if unzip -Z1 "$DEST/$l.xcframework.zip" | grep -q -E '(^|/)(__MACOSX|\._)'; then
    echo "$l.xcframework.zip contains Mac metadata" >&2; exit 1
  fi
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

# Licence texts, copied unchanged from the verified source tarballs.
lock_file() { awk -F'|' -v n="$1" '$1==n{print $2}' "$ROOT/sources.lock"; }
lic() {  # <sources.lock name> <path inside the tarball's top folder> <asset name>
  local tgz top
  tgz="$ROOT/downloads/$(lock_file "$1")"
  top="$(tar -tzf "$tgz" | head -1 | cut -d/ -f1)"
  tar -xzOf "$tgz" "$top/$2" > "$DEST/$3"
  [[ -s "$DEST/$3" ]] || { echo "empty $3 from $1:$2" >&2; exit 1; }
}
lic ffmpeg     COPYING.LGPLv3 license-LGPL-3.0.txt
lic ffmpeg     COPYING.GPLv3  license-GPL-3.0.txt
lic ffmpeg     LICENSE.md     license-FFmpeg-LICENSE.md
lic ffmpeg-kit LICENSE        license-ffmpeg-kit.txt
lic freetype   docs/FTL.TXT   license-FreeType-FTL.txt
lic harfbuzz   COPYING        license-HarfBuzz-COPYING.txt
lic libpng     LICENSE        license-libpng-LICENSE.txt
lic dlg        LICENSE        license-dlg-LICENSE.txt
cat > "$DEST/NOTICE.txt" <<NOTICE
CamTape FFmpeg build, release $TAG
Source and build recipe: $REPO (tag $TAG)

The eight xcframeworks (ffmpegkit, libavcodec, libavdevice, libavfilter,
libavformat, libavutil, libswresample, libswscale) are dynamic libraries
licensed under the GNU Lesser General Public License, version 3 or later
(license-LGPL-3.0.txt, which refers to the GNU General Public License,
version 3: license-GPL-3.0.txt). The complete source is the source-*
files of this release together with the repository at tag $TAG.

Components and their licences:

  FFmpeg n8.1.2 (arthenica fork)   LGPL v3 or later      license-FFmpeg-LICENSE.md
  ffmpeg-kit android-apple-8.1.2   LGPL v3               license-ffmpeg-kit.txt
    Copyright (c) 2018-2022 Taner Sener and contributors.
  FreeType 2.13.3                  FreeType License      license-FreeType-FTL.txt
    Portions of this software are copyright (c) The FreeType Project
    (www.freetype.org). All rights reserved.
  HarfBuzz 11.3.3                  "Old MIT"             license-HarfBuzz-COPYING.txt
  libpng 1.6.40                    libpng License        license-libpng-LICENSE.txt
  dlg 72dfcc8                      Boost Software License 1.0  license-dlg-LICENSE.txt

FreeType, HarfBuzz and libpng are linked statically into libavfilter
(confirmed in the built library). dlg is part of the FreeType source used
by this build (FreeType's subprojects/dlg); it has not been confirmed to
be included in libavfilter. Its licence is included because it is part of
that source.
gnu-config and gas-preprocessor are build tools only; they are not part
of the libraries.
NOTICE
(cd "$DEST" && shasum -a 256 license-* NOTICE.txt) >> "$DEST/checksums.txt"
echo "$DEST"
ls -la "$DEST"
