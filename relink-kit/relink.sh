#!/bin/bash
# Put your own build of the FFmpeg libraries into CamTape and sign it so it
# runs on your iPhone. See README.md in this folder.
#
#   ./relink.sh --app Runner.app --frameworks DIR --bundle-id ID \
#               --profile PROFILE.mobileprovision [--identity NAME] \
#               [--device UDID] [--out DIR]
#
#   --app         Runner.app from the CamTape relink kit (unsigned)
#   --frameworks  your build: an out/<stamp> folder from build.sh (xcframeworks),
#                 or a folder of .framework bundles. Every FFmpeg framework
#                 found there replaces the one in the app.
#   --bundle-id   a bundle ID your provisioning profile allows
#   --profile     your development provisioning profile
#   --identity    your signing identity (default "Apple Development";
#                 "-" signs ad hoc, which a device will not run)
#   --device      install on this device (UDID) with devicectl
#   --out         where to write the signed app (default ./relinked)
#
# The kit's Runner.app is copied, never changed.
set -euo pipefail

APP_IN="" FW="" BUNDLE="" PROFILE="" IDENTITY="Apple Development" DEVICE="" OUT="./relinked"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP_IN="$2"; shift 2 ;;
    --frameworks) FW="$2"; shift 2 ;;
    --bundle-id) BUNDLE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ -d "$APP_IN" && -d "$FW" && -n "$BUNDLE" ]] || { sed -n '2,20p' "$0"; exit 2; }
[[ "$IDENTITY" == "-" || -f "$PROFILE" ]] || { echo "--profile is required" >&2; exit 2; }

LIBS=(ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)
mkdir -p "$OUT"
APP="$OUT/Runner.app"
[[ -e "$APP" ]] && mv "$APP" "$OUT/Runner.app.previous.$(date +%s)"
cp -R "$APP_IN" "$APP"

# 1. Replace the frameworks.
swapped=0
for l in "${LIBS[@]}"; do
  src=""
  if [[ -d "$FW/$l.xcframework/ios-arm64/$l.framework" ]]; then
    src="$FW/$l.xcframework/ios-arm64/$l.framework"
  elif [[ -d "$FW/$l.framework" ]]; then
    src="$FW/$l.framework"
  fi
  [[ -n "$src" ]] || continue
  mv "$APP/Frameworks/$l.framework" "$OUT/$l.framework.replaced.$(date +%s)"
  cp -R "$src" "$APP/Frameworks/$l.framework"
  echo "replaced $l.framework"
  swapped=$((swapped + 1))
done
[[ $swapped -gt 0 ]] || { echo "no FFmpeg frameworks found in $FW" >&2; exit 1; }

# 2. Check what the app will load: install name, architecture, minimum iOS.
for l in "${LIBS[@]}"; do
  bin="$APP/Frameworks/$l.framework/$l"
  id="$(otool -D "$bin" | tail -1)"
  arch="$(lipo -archs "$bin")"
  minos="$(otool -l "$bin" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
  printf '%-14s %s %s minos %s\n' "$l" "$id" "$arch" "$minos"
  [[ "$id" == "@rpath/$l.framework/$l" ]] || { echo "  install name must be @rpath/$l.framework/$l" >&2; exit 1; }
  [[ "$arch" == arm64 ]] || { echo "  must be arm64 (device)" >&2; exit 1; }
done

# 3. Your bundle ID, profile and entitlements.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE" "$APP/Info.plist"
ENT="$OUT/entitlements.plist"
if [[ "$IDENTITY" != "-" ]]; then
  cp "$PROFILE" "$APP/embedded.mobileprovision"
  security cms -D -i "$PROFILE" > "$OUT/profile.plist"
  TEAM="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$OUT/profile.plist")"
  cat > "$ENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>$TEAM.$BUNDLE</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM</string>
  <key>get-task-allow</key><true/>
</dict></plist>
PLIST
else
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n' > "$ENT"
fi

# 4. Sign from the inside out.
for fw in "$APP"/Frameworks/*.framework; do
  codesign --force --sign "$IDENTITY" --timestamp=none "$fw"
done
codesign --force --sign "$IDENTITY" --timestamp=none --entitlements "$ENT" "$APP"
codesign --verify --deep --strict "$APP"
echo "signed: $APP"

# 5. Install.
if [[ -n "$DEVICE" ]]; then
  xcrun devicectl device install app --device "$DEVICE" "$APP"
fi
