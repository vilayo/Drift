# Drift

A small native live wallpaper app for macOS, built with an 8 GB MacBook Air in mind.

Drift plays silent video loops behind your desktop icons using AppKit and AVFoundation.
Its menu bar controls and power policy keep animation out of the way when your Mac
has more useful work to do.

## Version 0.2

- Original **Quiet Current** wallpaper included in app builds: 720p, 15 fps, 12-second loop.
- New **Quiet Current · Smooth** wallpaper: **1080p, 60 fps**, 12-second loop.
- Import local videos with quality presets up to **4K at 60 fps**, without audio.
- Select one display at a time; the built-in screen is preferred by default.
- Pause, resume, change wallpapers, or turn the wallpaper off from native controls.
- Pause on battery and when other windows cover the desktop, both enabled by default.
- Automatically pause for Low Power Mode, battery below 15%, serious or critical heat,
  memory pressure, screen lock, and display/system sleep.
- Release the player and decoder queue when paused; show a still poster instead.
- Optional open at login. First launch leaves the wallpaper off until you choose one.
- Settings close completely while the menu bar app continues running.

### Choose a quality preset

| Import quality | Maximum resolution | Maximum frame rate |
| --- | --- | --- |
| Eco (default) | 1280 × 720 | 24 fps |
| Balanced | 1920 × 1080 | 30 fps |
| Smooth | 1920 × 1080 | 60 fps |
| Ultra | 3840 × 2160 | 60 fps |

Choose **Import quality** before importing a video. The preset is a ceiling: Drift
does not enlarge a smaller video or turn 24/30 fps footage into 60 fps. Fractional
source rates such as 59.94 fps retain their cadence instead of being rounded to an
integer before export. The finished file is checked for its actual dimensions and
frame rate. Ultra exports use HEVC; the other presets use H.264.

Quality applies to **new imports**. Reimport the original file at a higher preset
to improve an old optimized copy. Existing libraries are preserved when upgrading;
the new import preference starts at Eco.

For an immediate 60 fps demo, select **Quiet Current · Smooth** in the wallpaper
menu. All power-saving pauses still apply. Smooth and Ultra can use more memory,
GPU work, and battery than Eco. The local measurements are in the performance notes.

This first version supports video wallpapers. Steam Workshop scenes, interactive
web wallpapers, and Wallpaper Engine project files are outside its current scope.

## Build and run

Requires macOS 14 or later and Apple's Command Line Tools with Swift 6 or later.
There are no third-party packages or runtime services.

```sh
git clone https://github.com/vilayo/Drift.git
cd Drift
bash scripts/build-app.sh
open dist/Drift.app
```

The build generates the original wallpaper locally, compiles a release app with
two build jobs, creates an icon, and applies an ad hoc signature. It also produces
`dist/Drift-macOS.zip`. The executable targets the build Mac's architecture.
The local build for the initial release was made on Apple Silicon.

You can move `Drift.app` to Applications. Use **Use wallpaper** to start, or
**Import video…** to choose a video between one second and five minutes long.
If you see **Saving battery**, connect power or switch off **Pause on battery power**.
If you see **Desktop is covered**, expose the desktop or change that preference.
Turning the wallpaper off or quitting reveals your existing macOS wallpaper.

This is a development build. Developer ID signing, notarization, and an automatic
updater are not configured yet. The login-item option depends on macOS approving
the installed app; any registration error is shown in the app.

## Resource use

See [the measured performance notes](docs/performance.md) for local CPU and memory
measurements and their limits. There is no universal memory or battery guarantee:
macOS, the video, displays, and other workloads all affect the result.

The app has one video player, no browser engine, no audio playback, no animated
settings preview, and no per-frame app timer. Desktop coverage is checked every
five seconds with a one-second timer tolerance only when other power rules allow
playback. Sleep, power-source, thermal, lock, and memory events use notifications.

## Test

The standalone runner uses the same 22 test methods as the XCTest suite and works
with Command Line Tools alone:

```sh
bash scripts/test-core.sh
```

With full Xcode selected, the package also supports:

```sh
swift test --jobs 2
```

The checks cover power-policy priority, low-battery boundaries, manual pause,
settings serialization, overlapping windows, split view, multiple-display geometry,
and quality limits, fractional frame rates, portrait sizing, and avoiding upscaling.
GitHub Actions runs XCTest and packages an app artifact.

The packaged app has isolated diagnostics. Always use a fresh absolute directory:

```sh
dist/Drift.app/Contents/MacOS/Drift --smoke-test --data-directory /tmp/drift-playback-check
dist/Drift.app/Contents/MacOS/Drift --import-smoke-test --data-directory /tmp/drift-import-check
dist/Drift.app/Contents/MacOS/Drift --import-smoke-test /path/to/video.mp4 --quality smooth --data-directory /tmp/drift-smooth-check
dist/Drift.app/Contents/MacOS/Drift --benchmark --data-directory /tmp/drift-benchmark-check
```

The playback check briefly replaces the desktop while it verifies an actual rendered
frame and eight window close/open cycles. The benchmark also briefly displays the
built-in wallpaper. Both remove their desktop window when finished. The import
check accepts an optional source file immediately after `--import-smoke-test` and
`--quality eco|balanced|smooth|ultra`. Playback and benchmark checks accept `--video`
followed by a local movie path. The default playback check uses the 1080p/60 fps
built-in wallpaper; the default benchmark uses the selected wallpaper.

## Privacy and storage

The app contains no network requests, account system, telemetry, or video uploads.
Imported originals are left untouched. Optimized movies, posters, and settings live
in `~/Library/Application Support/Drift/`. Removing a library wallpaper moves the
optimized copies to Trash. Your original file stays where you put it.

Desktop coverage reads window bounds, layers, owner process IDs, and opacity through
Quartz metadata. It does not read window titles, take screenshots, or request Screen
Recording or Accessibility permission. Coverage is a geometry heuristic, so unusual
transparent windows, Spaces, full-screen apps, and Stage Manager need broader testing.

More implementation detail is in [architecture.md](docs/architecture.md).
