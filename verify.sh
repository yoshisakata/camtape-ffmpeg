#!/bin/bash
# Checks a build in out/<stamp>/ :
#   licence (LGPL v3, no --enable-gpl / --enable-nonfree),
#   components in required-components.txt,
#   architectures, install names and minimum iOS of every framework.
# Prints PASS/FAIL lines; exits 1 if anything failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?usage: verify.sh out/<stamp>}"
COMP="$OUT/components"
fail=0
pass() { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }

# ---- licence, from the device libavutil itself
AVUTIL="$OUT/libavutil.xcframework/ios-arm64/libavutil.framework/libavutil"
lic="$(strings -a "$AVUTIL" | sed -n 's/^libavutil license: //p' | head -1)"
conf="$(strings -a "$AVUTIL" | grep -m1 -- '--prefix=' || true)"
[[ "$lic" == "LGPL version 3 or later" ]] && pass "licence: $lic" || bad "licence: '$lic'"
for flag in --enable-gpl --enable-nonfree --enable-libx264 --enable-libx265; do
  [[ "$conf" == *"$flag"* ]] && bad "configure has $flag" || pass "configure has no $flag"
done
[[ "$conf" == *--enable-version3* ]] && pass "configure has --enable-version3" || bad "configure lacks --enable-version3"

# ---- components, from the generated lists copied by build.sh
has() { # kind name
  case "$1" in
    filter)   grep -qE "&ff_[a-z]+_$2," "$COMP/filter_list.c" ;;
    encoder)  grep -qE "&ff_$2_encoder," "$COMP/codec_list.c" ;;
    decoder)  grep -qE "&ff_$2_decoder," "$COMP/codec_list.c" ;;
    muxer)    grep -qE "&ff_$2_muxer," "$COMP/muxer_list.c" ;;
    demuxer)  grep -qE "&ff_$2_demuxer," "$COMP/demuxer_list.c" ;;
    protocol) grep -qE "&ff_$2_protocol," "$COMP/protocol_list.c" ;;
    hwaccel)  grep -qE "^#define CONFIG_$(echo "$2" | tr a-z A-Z)_HWACCEL 1" "$COMP/config_components.h" ;;
  esac
}
while read -r a b c; do
  [[ -z "$a" || "$a" == \#* ]] && continue
  if [[ "$a" == absent ]]; then
    has "$b" "$c" && bad "$b $c is present" || pass "no $b $c"
  else
    has "$a" "$b" && pass "$a $b" || bad "$a $b missing"
  fi
done <"$ROOT/required-components.txt"

# ---- frameworks
for xcf in "$OUT"/*.xcframework; do
  name="$(basename "$xcf" .xcframework)"
  for slice in ios-arm64 ios-arm64-simulator; do
    bin="$xcf/$slice/$name.framework/$name"
    [[ -f "$bin" ]] || { bad "$name $slice missing"; continue; }
    archs="$(lipo -archs "$bin")"
    id="$(otool -D "$bin" | tail -1)"
    plat="$(otool -l "$bin" | awk '/LC_BUILD_VERSION/{f=1} f&&/platform/{p=$2} f&&/minos/{print p" "$2; exit}')"
    [[ "$archs" == arm64 ]] || bad "$name $slice archs $archs"
    [[ "$id" == "@rpath/$name.framework/$name" ]] || bad "$name $slice id $id"
    pass "$name $slice arm64 $id platform/minos $plat"
    # nothing outside the system and the other frameworks
    otool -L "$bin" | tail -n +2 | awk '{print $1}' | while read -r dep; do
      case "$dep" in
        /usr/lib/*|/System/Library/*|@rpath/lib*.framework/*|@rpath/ffmpegkit.framework/*) ;;
        # Apple's Swift runtime (/usr/lib/swift). With the iOS 27 SDK and an
        # older deployment target, ld binds some CoreMedia functions through
        # libswiftCoreMedia. The app must have /usr/lib/swift in its rpath.
        @rpath/libswiftCoreMedia.dylib) echo "NOTE  $name $slice links $dep (app needs /usr/lib/swift in rpath)" ;;
        *) echo "FAIL  $name $slice links $dep" ;;
      esac
    done
  done
done >"$OUT/VERIFY-frameworks.txt"
cat "$OUT/VERIFY-frameworks.txt"
grep -q '^FAIL' "$OUT/VERIFY-frameworks.txt" && fail=1

[[ $fail -eq 0 ]] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit $fail
