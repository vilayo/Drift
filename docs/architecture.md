# Architecture

## Components

| Component | Responsibility |
| --- | --- |
| `DriftMain` / `AppDelegate` | Native process, menu bar, settings actions, and playback coordination |
| `LibraryStore` | Atomic JSON settings and local media paths |
| `VideoImporter` | Bounded video export, audio removal, orientation, and small poster generation |
| `WallpaperEngine` | One click-through desktop window, one AVQueuePlayer, and AVPlayerLooper |
| `SystemMonitor` | Power, thermal, sleep, session lock, memory pressure, and desktop coverage |
| `DriftCore` | Pure playback policy and exact rectangle-union coverage calculation |
| `PreferencesWindow` | AppKit settings controls and a single static preview |

## Playback lifecycle

1. First launch leaves playback disabled. A chosen wallpaper starts only after the user enables it.
2. An opaque borderless window sits at the desktop window level plus one, below desktop icons.
   It ignores input, joins Spaces, and does not participate in normal window cycling.
3. A static poster is shown first. A single AVPlayerLayer displays the muted AVQueuePlayer
   after its first frame is ready. The player never prevents display sleep.
4. Any pause reason detaches the layer, pauses the player, disables looping, empties the
   queue, and releases the player. A small poster remains. A remembered playback time
   is used on resume.
5. Turning off, changing the selected media/display, or quitting removes the old desktop
   window. Swift owns the window; `isReleasedWhenClosed` is false and window animations
   are disabled to avoid an AppKit closing-animation lifetime error.

The engine observes player-item failures and reports them through the settings window.
It does not set the system wallpaper or modify Apple's wallpaper agent data.

## Power policy

Priority order: disabled → manual pause/import → sleep → lock → Low Power Mode →
serious/critical thermal state → memory pressure → battery below 15% → battery
preference → covered-desktop preference → playback.

Preferences cannot override system protection. A manual pause survives unrelated
power events for the lifetime of the process. The enabled state and energy preferences
persist; manual pause resets at the next launch.

Coverage uses the exact union of on-screen, opaque, normal-layer windows over the
selected screen's visible frame. This avoids counting overlapping windows twice.
At least 98% coverage pauses playback. The geometry calculation is tested independently.
Quartz metadata contains no captured screen pixels. Window titles are not read.

There is one five-second coverage timer with a one-second tolerance when playback is
otherwise allowed. The timer remains active while coverage itself is the pause reason,
so moving a window away can resume playback. Power, sleep, manual pause, and thermal
constraints stop that timer.

## Import budget

Only one import runs at a time, and active wallpaper playback pauses during import.
The input must have a video track and a duration of 1–300 seconds. A composition copies
only the video track. Its preferred transform is normalized before scaling to even
dimensions within the selected quality limits. `VideoImportPlan` computes those limits
in the testable core module, without enlarging a small source or increasing its frame rate.

Eco is 1280 × 720 / 24 fps, Balanced is 1920 × 1080 / 30 fps, Smooth is 1920 × 1080 /
60 fps, and Ultra is 3840 × 2160 / 60 fps. Fractional frame duration uses a 600,000
timescale so common 1000/1001 cadences do not get rounded to integer frame rates.
The output track is checked and its actual dimensions and nominal frame rate are
stored in the library. No audio track is written.

Export uses macOS's H.264 720p or 1080p presets, or the HEVC 4K preset for Ultra, and
a video composition. Poster limits are 640 × 360 for Eco, 1280 × 720 for Balanced and
Smooth, and 1920 × 1080 for Ultra. The playback item has no fixed 720p resolution or
bitrate preference. Its local optimized file determines playback quality.

There are two generated built-in wallpapers: 720p/15 fps and 1080p/60 fps. Quality
selection applies to future imports; existing optimized media is never silently
replaced or enlarged. The original input is never modified. An incomplete import is
cleaned up, and saving a library update is atomic.

Settings decoding supplies Eco when an older library has no quality key. Wallpaper
frame rates are stored as doubles, which also decode the integer frame rates saved
by version 0.1.

## Platform APIs

- [AVPlayerLooper](https://developer.apple.com/documentation/avfoundation/avplayerlooper)
- [Video export presets](https://developer.apple.com/documentation/avfoundation/export-presets)
- [NSWindow collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)
- [Power-source change notifications](https://developer.apple.com/documentation/iokit/1523868-iopsnotificationcreaterunloopsou)
- [Thermal change notifications](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification)

Session lock/unlock uses macOS distributed notifications, with the current Quartz
session dictionary used for the initial lock state. This behavior should be checked
on each newly supported macOS release.
