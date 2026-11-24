#!/bin/bash
# Builds the FFmpeg (LGPL v3) xcframeworks that CamTape ships.
#
#   ./build.sh                      fetch (if needed), verify, build, check
#   ./build.sh --patches DIR        same, with your own patches applied
#
# Sources: only the tarballs listed in sources.lock, checked by sha256.
# Build:   the ffmpeg-kit (sk3llo, android-apple-8.1.2) scripts, unmodified
#          except for the changes listed under "Build-tree changes" below.
# Output:  out/<stamp>/*.xcframework, BUILD-INFO.txt, VERIFY.txt
#          (the full build.log stays in work/<stamp>/ffmpeg-kit/)
#
# Each run uses a fresh work/<stamp>/ folder and never deletes anything.
#
# Needs: Xcode (iOS SDK), Homebrew pkgconf, autoconf, automake, libtool,
#        and cmake. No sudo.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# --patches DIR : extra patches to apply (DIR/<lib>/*.patch), e.g. your own
#                 changes to FFmpeg or ffmpeg-kit. Recorded in BUILD-INFO.txt.
USER_PATCHES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --patches) USER_PATCHES="$(cd "$2" && pwd)"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
DL="$ROOT/downloads"
STAMP="$(date +%Y%m%d-%H%M%S)"
# The work tree lives at a neutral path: FFmpeg records its configure line
# (with --prefix) in the libraries, so building under a home folder would
# put the account name into the published binaries.
WORK_BASE="${CAMTAPE_FFMPEG_WORK:-/tmp/camtape-ffmpeg-work}"
# Resolve links (/tmp is /private/tmp on macOS): the scripts and the git
# stand-in must see the same spelling of every path.
mkdir -p "$WORK_BASE"
WORK_BASE="$(cd "$WORK_BASE" && pwd -P)"
WORK="$WORK_BASE/$STAMP"
OUT="$ROOT/out/$STAMP"
KIT="$WORK/ffmpeg-kit"

# The only options passed to ffmpeg-kit's ios.sh.
#  - arm64 device + arm64 simulator only.
#  - VideoToolbox / AudioToolbox / zlib / bzip2 from the iOS SDK.
#  - FreeType + HarfBuzz for drawtext (the date stamp). No fontconfig:
#    CamTape always passes a font file.
#  - No --enable-gpl and no GPL libraries: the result is LGPL v3.
IOS_SH_OPTIONS=(
  --disable-armv7 --disable-armv7s --disable-arm64e
  --disable-i386 --disable-x86-64
  --disable-arm64-mac-catalyst --disable-x86-64-mac-catalyst
  --enable-ios-videotoolbox --enable-ios-audiotoolbox
  --enable-ios-zlib --enable-ios-bzip2
  --enable-freetype --enable-harfbuzz
  --xcframework
)

log() { printf '[build] %s\n' "$*"; }

# ---------------------------------------------------------------- sources
fetch_and_verify() {
  mkdir -p "$DL"
  while IFS='|' read -r name file url sha; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    local path="$DL/$file"
    if [[ ! -f "$path" ]]; then
      log "fetch $name"
      curl -fsSL -o "$path.part" "$url"
      mv "$path.part" "$path"
    fi
    local got
    got="$(shasum -a 256 "$path" | awk '{print $1}')"
    if [[ "$got" != "$sha" ]]; then
      echo "sha256 mismatch for $file: $got (expected $sha)" >&2
      exit 1
    fi
    log "ok    $name $sha"
  done <"$ROOT/sources.lock"
}

file_of() { awk -F'|' -v n="$1" '$1==n {print $2}' "$ROOT/sources.lock"; }

untar_into() { # tarball dest
  mkdir -p "$2"
  tar -xzf "$DL/$1" -C "$2" --strip-components 1
}

# ---------------------------------------------------------------- prepare
APPLIED_PATCHES=()
apply_patches() { # dir
  local dir="$1" p lib target
  for p in "$dir"/*/*.patch; do
    [[ -f "$p" ]] || continue
    lib="$(basename "$(dirname "$p")")"
    if [[ "$lib" == ffmpeg-kit ]]; then target="$KIT"; else target="$KIT/src/$lib"; fi
    [[ -d "$target" ]] || { echo "patch $p: no source folder for '$lib'" >&2; exit 1; }
    log "patch $lib/$(basename "$p")"
    patch -s -p1 -d "$target" <"$p"
    APPLIED_PATCHES+=("$p")
  done
}

prepare_tree() {
  log "work  $WORK"
  untar_into "$(file_of ffmpeg-kit)" "$KIT"
  untar_into "$(file_of ffmpeg)" "$KIT/src/ffmpeg"
  untar_into "$(file_of freetype)" "$KIT/src/freetype"
  # FreeType's git submodule (subprojects/dlg), at the commit FreeType pins.
  untar_into "$(file_of dlg)" "$KIT/src/freetype/subprojects/dlg"
  untar_into "$(file_of harfbuzz)" "$KIT/src/harfbuzz"
  untar_into "$(file_of libpng)" "$KIT/src/libpng"
  untar_into "$(file_of gnu-config)" "$KIT/.tmp/source/config"

  # gas-preprocessor: placed where the scripts would download it, with
  # the same one-line patch they apply after downloading.
  cp "$DL/$(file_of gas-preprocessor)" "$KIT/.tmp/gas-preprocessor.pl"
  chmod +x "$KIT/.tmp/gas-preprocessor.pl"
  sed -i .tmp "s/s\+({/s\+(\\\\{/g;s/s\*})/s\*\\\\})/g" "$KIT/.tmp/gas-preprocessor.pl"

  # ---- Build-tree changes (the only differences from the ffmpeg-kit tag)
  # 1. freetype.sh runs `sudo make`. Building needs no root.
  sed -i '' 's/^sudo make /make /' "$KIT/scripts/apple/freetype.sh"
  # 2. HarfBuzz 11.x has no autotools; build it with CMake instead.
  cp "$ROOT/overrides/scripts/apple/harfbuzz.sh" "$KIT/scripts/apple/harfbuzz.sh"
  # 3. main-ios.sh waits for fontconfig before building HarfBuzz, although
  #    HarfBuzz only depends on FreeType (function.sh: harfbuzz -> freetype).
  #    Without fontconfig enabled that loop never ends.
  sed -i '' 's/if \[\[ \$OK_fontconfig -eq 1 \]\] \&\& \[\[ \$OK_freetype -eq 1 \]\]; then/if [[ $OK_freetype -eq 1 ]]; then/' \
    "$KIT/scripts/main-ios.sh"
  if grep -q 'OK_fontconfig -eq 1 ]] && \[\[ \$OK_freetype' "$KIT/scripts/main-ios.sh"; then
    echo "main-ios.sh harfbuzz condition not changed" >&2; exit 1
  fi
  # 4. Source patches: overrides/patches/<lib>/*.patch, then the caller's
  #    own patches (--patches DIR, same layout). <lib> is a folder under
  #    src/ (ffmpeg, freetype, harfbuzz, libpng) or "ffmpeg-kit" for the
  #    ffmpeg-kit tree itself (apple/src/...). Applied with patch -p1.
  apply_patches "$ROOT/overrides/patches"
  [[ -n "$USER_PATCHES" ]] && apply_patches "$USER_PATCHES"

  # A clean copy of the prepared sources. The git stand-in restores files
  # from it when the scripts undo their per-architecture edits.
  cp -R "$KIT/src" "$WORK/pristine-src"
}

# ---------------------------------------------------------------- build
run_build() {
  log "ios.sh ${IOS_SH_OPTIONS[*]}"
  (
    cd "$KIT"
    # A clean environment: ffmpeg-kit writes every environment variable
    # into build.log, so pass only what the build needs (no tokens or keys).
    env -i \
      HOME="$HOME" USER="$USER" LOGNAME="${LOGNAME:-$USER}" SHELL=/bin/bash \
      LANG=en_US.UTF-8 TMPDIR="${TMPDIR:-/tmp}" \
      PATH="$ROOT/tools/git-shim:$(brew --prefix)/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
      CAMTAPE_SRC="$KIT/src" CAMTAPE_PRISTINE="$WORK/pristine-src" \
      ./ios.sh "${IOS_SH_OPTIONS[@]}"
  ) | tee "$WORK/ios-sh-console.txt" &
  local job=$!
  # Watchdog: ios.sh retries a library whose dependencies are not ready,
  # forever. If it keeps skipping, stop instead of spinning.
  while kill -0 "$job" 2>/dev/null; do
    sleep 20
    if [[ "$(grep -c '^INFO: Skipping' "$KIT/build.log" 2>/dev/null || echo 0)" -gt 2000 ]]; then
      echo "build stuck: a library's dependencies never finished (see build.log)" >&2
      pkill -f "$KIT/" || true
      exit 1
    fi
  done
  wait "$job" || true
  # ios.sh prints its own errors but can exit 0 after a failed library.
  if [[ ! -d "$KIT/prebuilt/bundle-apple-xcframework-ios/ffmpegkit.xcframework" ]]; then
    echo "build failed: see $KIT/build.log" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------- collect
collect() {
  mkdir -p "$OUT"
  cp -R "$KIT/prebuilt/bundle-apple-xcframework-ios/"*.xcframework "$OUT/"

  # The component lists FFmpeg's configure generated (last architecture
  # built; every architecture uses the same options). verify.sh reads them.
  mkdir -p "$OUT/components"
  local ff="$KIT/src/ffmpeg"
  cp "$ff/libavfilter/filter_list.c" "$ff/libavcodec/codec_list.c" \
     "$ff/libavformat/muxer_list.c" "$ff/libavformat/demuxer_list.c" \
     "$ff/libavformat/protocol_list.c" "$ff/config_components.h" \
     "$OUT/components/"

  local info="$OUT/BUILD-INFO.txt"
  {
    echo "CamTape FFmpeg build $STAMP"
    echo
    echo "== Host"
    sw_vers | sed 's/^/  /'
    echo "  $(xcodebuild -version | tr '\n' ' ')"
    echo "  iOS SDK $(xcrun --sdk iphoneos --show-sdk-version)"
    for t in pkgconf autoconf automake glibtool cmake; do
      printf '  %s %s\n' "$t" "$("$t" --version 2>/dev/null | head -1 | awk '{print $NF}')"
    done
    echo
    echo "== Sources (sources.lock)"
    grep -v '^#' "$ROOT/sources.lock" | awk -F'|' '{printf "  %-16s %s\n  %-16s sha256 %s\n", $1, $3, "", $4}'
    echo
    echo "== Build-tree changes"
    echo "  scripts/apple/freetype.sh: 'sudo make' -> 'make'"
    echo "  scripts/apple/harfbuzz.sh: replaced by overrides/scripts/apple/harfbuzz.sh (CMake)"
    echo "  scripts/main-ios.sh: HarfBuzz waits for FreeType only (not fontconfig)"
    for p in "${APPLIED_PATCHES[@]}"; do
      echo "  patch: ${p#"$ROOT"/} (sha256 $(shasum -a 256 "$p" | awk '{print $1}'))"
    done
    echo "  git: tools/git-shim/git ('describe' answers the tag; 'checkout' restores from the clean copy of the sources)"
    echo
    echo "== ios.sh options"
    echo "  ${IOS_SH_OPTIONS[*]}"
    echo
    echo "== FFmpeg configure (from the arm64 device libavutil)"
    strings -a "$OUT/libavutil.xcframework/ios-arm64/libavutil.framework/libavutil" \
      | grep -m1 -- '--prefix=' | sed 's/^/  /'
    echo
    echo "== Frameworks (sha256 of each binary)"
    (cd "$OUT" && find . -path '*.framework/*' -type f -perm -u+x \
        ! -name '*.plist' -print0 | sort -z | xargs -0 shasum -a 256 | sed 's/^/  /')
  } >"$info"
  log "out   $OUT"
}

fetch_and_verify
prepare_tree
run_build
collect
"$ROOT/verify.sh" "$OUT" | tee "$OUT/VERIFY.txt"
