# CamTape FFmpeg build

The FFmpeg libraries in the CamTape iOS app are built here, from source,
under the **GNU LGPL version 3 or later**. This folder is the build recipe
and the source for those libraries.

CamTape links them dynamically (`@rpath/*.framework`). You can build a
modified version with this recipe and use it in place of the shipped one;
see "Replacing the libraries" (relink kit, added per release).

## What is built

| Part | Version | License |
|---|---|---|
| FFmpeg (arthenica fork used by ffmpeg-kit) | n8.1.2 | LGPL v3 or later (`--enable-version3`, no `--enable-gpl`) |
| ffmpeg-kit (sk3llo) | android-apple-8.1.2 | LGPL v3 |
| FreeType | 2.13.3 | FreeType License (FTL) |
| HarfBuzz | 11.3.3 | MIT ("Old MIT") |
| libpng | 1.6.40 | libpng License |
| dlg (FreeType's submodule) | 72dfcc8 | Boost Software License 1.0 |

zlib, bzip2, VideoToolbox and AudioToolbox come from the iOS SDK.
No GPL or non-free libraries are enabled. libx264, libx265, fontconfig,
fribidi and libass are not included.

Output: eight xcframeworks (`ffmpegkit`, `libavcodec`, `libavdevice`,
`libavfilter`, `libavformat`, `libavutil`, `libswresample`, `libswscale`),
each with `ios-arm64` and `ios-arm64-simulator` slices.

## Files

| File | What it is |
|---|---|
| `sources.lock` | Every source tarball: URL and sha256 |
| `build.sh` | Fetches and checks the sources, prepares a fresh work tree, runs ffmpeg-kit's `ios.sh`, collects the output |
| `verify.sh` | Checks a build: licence string, configure options, required components, architectures, install names |
| `required-components.txt` | Filters, codecs and formats the app needs (and GPL ones that must be absent) |
| `overrides/scripts/apple/harfbuzz.sh` | Replaces ffmpeg-kit's HarfBuzz script (HarfBuzz 11 has no autotools; this uses its CMake build) |
| `relink-kit/` | `relink.sh` and the guide for running CamTape with your own build (see `relink-kit/README.md`) |
| `tools/package-release.sh` | Zips the xcframeworks, computes their Swift Package Manager checksums and gathers the source tarballs for a GitHub release |
| `tools/git-shim/git` | The ffmpeg-kit scripts expect a git checkout. This answers `git describe` with the release tag, restores files for `git checkout <path>` from a clean copy of the verified sources (the scripts undo their per-architecture edits this way), and refuses everything else, so no source is fetched by git |

The only changes to the ffmpeg-kit tag are made by `build.sh` in the work
tree: `sudo make` becomes `make` in `freetype.sh`, `harfbuzz.sh` is
replaced, `main-ios.sh` lets HarfBuzz wait for FreeType only (it waited
for fontconfig, which is not built, forever), and the source patches in `overrides/patches/` are applied
(`libpng/1.6.40-no-fp-h.patch`: the upstream 1.6.41 fix for current Apple
SDKs). All are recorded in each build's `BUILD-INFO.txt`.

## Building

Requirements: macOS with Xcode (iOS SDK), and from Homebrew:
`pkgconf autoconf automake libtool cmake`. No root access is needed.

```bash
./build.sh
```

Each run creates a build tree in `/tmp/camtape-ffmpeg-work/<stamp>/` (set
`CAMTAPE_FFMPEG_WORK` to use another place; FFmpeg records the build path in
its libraries, so a neutral path keeps your account name out of them) and
`out/<stamp>/`:

- `*.xcframework`
- `BUILD-INFO.txt` — host, tools, sources, options, sha256 of every binary
- `VERIFY.txt` — the `verify.sh` result
- `components/` — the component lists FFmpeg's configure generated

The full log is `/tmp/camtape-ffmpeg-work/<stamp>/ffmpeg-kit/build.log`. `ios.sh` runs with a
minimal environment (PATH, HOME, TMPDIR, locale), because ffmpeg-kit writes
every environment variable into that log.

Nothing is deleted between runs.

Note: built with the iOS 27 SDK, the device slices link
`@rpath/libswiftCoreMedia.dylib` (Apple's Swift runtime in `/usr/lib/swift`;
ld binds a few CoreMedia functions there for older deployment targets).
An app using these frameworks needs `/usr/lib/swift` in its runpath search
paths, which Xcode sets for apps that contain Swift.

### Building a modified version

Put your changes as patches in a folder, one sub-folder per source:

```
my-patches/
  ffmpeg/0001-my-change.patch       applied to FFmpeg (src/ffmpeg)
  ffmpeg-kit/0001-my-change.patch   applied to the ffmpeg-kit tree (apple/src/...)
  freetype/ harfbuzz/ libpng/       likewise
```

Make each patch with `diff -u` (or `git diff`) from the source's top folder,
so it applies with `patch -p1`. Then:

```bash
./build.sh --patches my-patches
```

The patches are listed, with their sha256, in that build's `BUILD-INFO.txt`.
You can also replace a tarball and its sha256 in `sources.lock`.

## Licences

The full texts of the LGPL v3 and the GPL v3 (which the LGPL v3 refers to)
are in the FFmpeg source (`COPYING.LGPLv3`, `COPYING.GPLv3`) and in the
ffmpeg-kit source (`LICENSE`).

## Releases

Each CamTape release that changes FFmpeg has a GitHub release here with:

- the eight `*.xcframework.zip` files CamTape's Swift package downloads
  (checksums in `checksums.txt`)
- every source tarball from `sources.lock` (`source-*`), with this
  repository's scripts and patches at that tag: the complete source for
  the shipped libraries
- `BUILD-INFO.txt` and `VERIFY.txt` for that build

Each CamTape App Store release also adds its relink kit
(`CamTape-<version>-<build>-relink-kit.zip`, see `relink-kit/README.md`).

