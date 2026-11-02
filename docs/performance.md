# Local performance and validation

Measured November 1, 2026 on an Apple M2 MacBook Air with 8 GiB of memory.
This is an early local measurement, not a guaranteed budget for every wallpaper.

## Final release-build sample

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
