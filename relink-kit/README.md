# Replacing FFmpeg in CamTape

CamTape uses the FFmpeg libraries under the GNU LGPL version 3 or later.
They are separate, dynamically linked frameworks, so you can build a
modified version and run CamTape with it on your own iPhone.

Each CamTape release has a **relink kit** on this repository's Releases
page: `CamTape-<version>-<build>-relink-kit.zip`. It contains:

- `Runner.app` — that release of CamTape before App Store encryption, with
  its signature removed
- `BUILD-INFO.txt` — the FFmpeg build that release ships (sources, options,
  sha256 of every library)
- `relink.sh` and this README

## What you need

- A Mac with Xcode and the Homebrew tools listed in the main README
- An Apple developer account (a free Apple ID may work, with Xcode's limits
  on free provisioning; this has not been tested)
- A development provisioning profile and signing identity for a bundle ID
  of your own (for example, make any app in Xcode with that bundle ID and
  run it on your iPhone once; Xcode creates both)
- Your iPhone with Developer Mode on (Settings › Privacy & Security)

## Steps

1. **Build your FFmpeg.** In this repository, with your changes as patches:

   ```bash
   ./build.sh --patches my-patches
   ```

   The result is in `out/<stamp>/`. Check `out/<stamp>/VERIFY.txt`.
   Your build must keep the same library names and major versions
   (`libavcodec.62`, `libavutil.60`, …) and the same ffmpegkit API, because
   CamTape's code calls them.

2. **Put it into CamTape and sign it.**

   ```bash
   relink-kit/relink.sh \
     --app CamTape-relink-kit/Runner.app \
     --frameworks out/<stamp> \
     --bundle-id com.example.mycamtape \
     --profile ~/Library/MobileDevice/Provisioning\ Profiles/<yours>.mobileprovision \
     --device <your iPhone's UDID>
   ```

   `xcrun devicectl list devices` shows the UDID. Without `--device` the
   signed app is left in `./relinked/Runner.app`.

3. **Open it on your iPhone.** It appears as a second CamTape (your bundle
   ID). In-app purchases and anything tied to the App Store bundle ID do not
   work in this copy; recording, finishing and exporting tapes do.

## What changes and what doesn't

Only the eight FFmpeg frameworks (`ffmpegkit`, `libavcodec`, `libavdevice`,
`libavfilter`, `libavformat`, `libavutil`, `libswresample`, `libswscale`)
are replaced. CamTape's own code (`Runner`, `App.framework`) is not
rebuilt; it is only signed again with your identity.
