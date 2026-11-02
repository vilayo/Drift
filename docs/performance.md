# Local performance and validation

Measured November 1, 2026 on an Apple M2 MacBook Air with 8 GiB of memory.
This is an early local measurement, not a guaranteed budget for every wallpaper.

## Version 0.2: higher quality and 60 fps

All four export presets were tested with a 3840 × 2160, 60 fps input:

| Preset | Exported size | Exported nominal rate | Audio tracks |
| --- | --- | ---: | ---: |
| Eco | 1280 × 720 | 24 fps | 0 |
| Balanced | 1920 × 1080 | 30 fps | 0 |
| Smooth | 1920 × 1080 | 60 fps | 0 |
| Ultra | 3840 × 2160 | 60 fps | 0 |

Ultra uses HEVC and the other presets use H.264. The 4K output rendered an actual
video frame, released its decoder on pause, and survived eight desktop-window
close/open cycles. A portrait input with audio exported to 606 × 1080 at 60 fps
with no audio. A fractional-rate source retained a non-integer cadence, with the
short exported file reporting about 59.95 fps nominally; file duration rounding
can slightly affect that nominal rate.

All 22 core checks pass. The new quality selector was checked in the native UI,
and its saved preference and the built-in 1080p/60 fps selection persisted. A
version 0.1 settings file with integer wallpaper frame rates and no quality key
loaded successfully and defaulted to Eco. Production memory-pressure pausing was
also observed in the native UI with the higher-quality selection active.

Two further isolated process benchmarks used the same timing as the baseline:

| Playing media | CPU, one core | Physical footprint | Resident memory | Paused CPU |
| --- | ---: | ---: | ---: | ---: |
| Built-in 1080p/60 H.264, 12-second loop | 3.34% | 19.0 MiB | 71.2 MiB | 0.04% |
| Imported 4K/60 HEVC, 2-second loop | 3.90% | 19.6 MiB | 61.4 MiB | 0.01% |

These are **Drift-process microbenchmarks**, with coverage polling disabled and
the selected default 720p poster used for both file overrides. Imported Ultra
wallpapers use a larger poster during normal operation, which can add memory.
Different codecs, loop lengths, and shared framework residency make the two rows
unsuitable as a strict comparison of total system cost. GPU, WindowServer,
system decoder memory, battery drain, and frame-drop measurements are excluded.
In particular, similar process memory does not mean 4K is as cheap as 1080p.
Raw samples are in [benchmark-quality.json](benchmark-quality.json).

## Version 0.1 baseline

The included Quiet Current wallpaper is 1280 × 720 H.264 at 15 fps. The settings
window was closed. Playback and pause each had a three-second settling period.
CPU is measured from process user + system time divided by elapsed wall time.
100% means one fully occupied CPU core. Memory is sampled at the end of each phase.

| State | Sample | CPU, one core | Physical footprint | Resident memory |
| --- | ---: | ---: | ---: | ---: |
| Wallpaper off | 10.5 s | 0.20% | 11.3 MiB | 55.1 MiB |
| Wallpaper playing | 20.1 s | 1.44% | 18.1 MiB | 58.9 MiB |
| Paused, decoder released | 10.5 s | 0.01% | 17.8 MiB | 59.4 MiB |

The player produced an actual video frame in the playback sample and was absent
in the paused sample. An earlier run measured about 1.5% CPU, 18.5 MiB physical
footprint, and 71.9 MiB resident during playback. Normal run-to-run variation and
shared library residency explain why a single number should not be treated as a cap.

Physical footprint and resident memory describe different things. Resident memory
includes shared framework pages. Releasing the player does not force macOS to discard
every cached page immediately.

**Scope:** These are Drift-process measurements. GPU work, WindowServer, video
decoder services, energy impact, and battery drain are not included. The isolated
engine benchmark disables desktop coverage polling so the wallpaper remains playing
even if the test desktop is covered. It is a short test, not an hours-long leak or
battery test. Importing and transcoding temporarily cost more than steady playback.

The exact samples and measurement context are in [benchmark.json](benchmark.json).
Use the `--benchmark` command in the main README to repeat the measurement on a new build.

## Validation performed

- Release app built and ad hoc signature verified on Apple Silicon.
- 13 shared power-policy and coverage test methods passed using the Command Line
  Tools runner. The local Command Line Tools installation does not include XCTest;
  the GitHub Actions workflow runs the XCTest version with full Xcode.
- The packaged ZIP was extracted elsewhere; its bundled video rendered and imported
  without relying on the source directory for media.
- Default import check: 1280 × 720 at 15 fps, no audio, poster created.
- Stress import check: 1920 × 1080 source at 60 fps, rotated to portrait and containing
  an audio track. Result: 404 × 720 at 24 fps, no audio, poster created.
- A rendered-frame playback check verified decoder release and eight subsequent
  desktop-window close/open cycles with the run loop alive.
- Native UI checks covered enabling, battery pause, covered-desktop pause, live
  playback, manual pause/resume, and turning the wallpaper off. Conservative energy
  preferences were restored after testing.
- Source diff whitespace, shell syntax, and the application property list were checked.

Battery drain over hours, sleep/wake transitions on physical hardware, external-display
hot-plugging, login-item approval, and broad Spaces/Stage Manager behavior still need
longer real-world testing. No hard memory or CPU limit is enforced by macOS on this app.
