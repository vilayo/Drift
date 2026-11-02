import AppKit
import AVFoundation
import DriftCore
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: LibraryStore!
    private var monitor: SystemMonitor!
    private let engine = WallpaperEngine()
    private var preferences: PreferencesWindow?
    private var statusItem: NSStatusItem!
    private var screenObserver: NSObjectProtocol?
    private var shownWallpaperID: String?
    private var shownDisplayID: UInt32?
    private var manuallyPaused = false
    private var importing = false
    private var playbackError: String?
    private var evaluating = false
    private var benchmark: Benchmark?
    private var runningDiagnostic = false
    private var lastReason: PauseReason? = .stopped
    private let smokeTest = CommandLine.arguments.contains("--smoke-test")

    private var screen: NSScreen? {
        if let id = store.settings.displayID, let screen = NSScreen.screens.first(where: { $0.displayID == id }) { return screen }
        return NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let args = CommandLine.arguments
            var directory: URL?
            if let index = args.firstIndex(of: "--data-directory"), args.indices.contains(index + 1) {
                directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            }
            store = try LibraryStore(directory: directory)
        } catch {
            if argsContains("--data-directory") && (smokeTest || argsContains("--benchmark") || argsContains("--import-smoke-test")) {
                fputs("DIAGNOSTIC_FAIL could not load library: \(error)\n", stderr); exit(1)
            }
            showError("Drift could not open its library: \(error.localizedDescription)")
            NSApp.terminate(nil); return
        }
        configureMenuBar()
        monitor = SystemMonitor()
        monitor.targetScreen = { [weak self] in self?.screen }
        monitor.onChange = { [weak self] in self?.evaluate() }
        engine.onError = { [weak self] message in self?.playbackError = message; self?.evaluate() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            self?.shownDisplayID = nil; self?.evaluate()
        }
        configureAppMenu()
        evaluate()
        runningDiagnostic = smokeTest || argsContains("--benchmark") || argsContains("--import-smoke-test")
        if argsContains("--benchmark") {
            guard argsContains("--data-directory"), let screen else { fputs("BENCHMARK_FAIL requires --data-directory and a display\n", stderr); exit(1) }
            benchmark = Benchmark(engine: engine, store: store, screen: screen, movieURL: diagnosticMovieURL())
            benchmark?.run { NSApp.terminate(nil) }
        } else if argsContains("--import-smoke-test") {
            runImportSmokeTest()
        } else if smokeTest {
            runPlaybackSmokeTest()
        } else if !store.settings.enabled || argsContains("--show-settings") {
            showPreferences(nil)
        }
    }

    private func argsContains(_ value: String) -> Bool { CommandLine.arguments.contains(value) }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "water.waves", accessibilityDescription: "Drift wallpapers")
        statusItem.button?.toolTip = "Drift · lightweight live wallpapers"
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
    }

    private func configureAppMenu() {
        let bar = NSMenu(), app = NSMenu()
        let item = NSMenuItem(); item.submenu = app; bar.addItem(item)
        app.addItem(withTitle: "Drift Settings…", action: #selector(showPreferences(_:)), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Drift", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Drift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit"), editItem = NSMenuItem(); editItem.submenu = edit; bar.addItem(editItem)
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        NSApp.mainMenu = bar
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let headline = NSMenuItem(title: statusText, action: nil, keyEquivalent: ""); headline.isEnabled = false
        menu.addItem(headline)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Drift…", action: #selector(showPreferences(_:)), keyEquivalent: ",").target = self
        if store.settings.enabled {
            menu.addItem(withTitle: manuallyPaused ? "Resume wallpaper" : "Pause wallpaper", action: #selector(togglePause(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Turn wallpaper off", action: #selector(stopWallpaper(_:)), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "Use \(store.selected.title)", action: #selector(useWallpaper(_:)), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        let battery = NSMenuItem(title: "Pause on battery power", action: #selector(toggleBatteryFromMenu(_:)), keyEquivalent: "")
        battery.target = self; battery.state = store.settings.energy.pauseOnBattery ? .on : .off; menu.addItem(battery)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Drift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private var statusText: String {
        if importing { return "Optimizing your video…" }
        if playbackError != nil { return "Playback needs attention · open Drift" }
        return lastReason?.title ?? "Playing · \(store.selected.title)"
    }

    private func evaluate() {
        guard !evaluating, !runningDiagnostic, monitor != nil else { return }
        evaluating = true
        defer { evaluating = false }
        var state = monitor.conditions
        state.enabled = store.settings.enabled; state.manuallyPaused = manuallyPaused || importing
        // Do not poll windows when another condition already requires a static wallpaper.
        var withoutCoverage = state; withoutCoverage.desktopCovered = false
        let canCheckCoverage = PlaybackPolicy.pauseReason(withoutCoverage, preferences: store.settings.energy) == nil
        monitor.monitorCoverage(canCheckCoverage && store.settings.energy.pauseWhenCovered && playbackError == nil)
        state.desktopCovered = monitor.conditions.desktopCovered
        lastReason = PlaybackPolicy.pauseReason(state, preferences: store.settings.energy)
        if !state.enabled {
            engine.stop(); shownWallpaperID = nil; shownDisplayID = nil
        } else if let screen {
            let selected = store.selected
            if shownWallpaperID != selected.id || shownDisplayID != screen.displayID {
                engine.show(posterURL: store.posterURL(for: selected), on: screen)
                shownWallpaperID = selected.id; shownDisplayID = screen.displayID
            }
            if lastReason == nil && playbackError == nil { engine.play(url: store.movieURL(for: selected)) }
            else { engine.suspend() }
        } else {
            engine.stop(); shownWallpaperID = nil; shownDisplayID = nil
        }
        statusItem.button?.appearsDisabled = !state.enabled
        statusItem.button?.toolTip = "Drift · \(statusText)"
        preferences?.refresh(store: store, status: statusText, manuallyPaused: manuallyPaused, importing: importing)
    }

    @objc private func showPreferences(_ sender: Any?) {
        if preferences == nil {
            let panel = PreferencesWindow(); preferences = panel
            panel.onClose = { [weak self] in
                DispatchQueue.main.async { self?.preferences = nil }
            }
            bind(panel.importButton, #selector(importVideo(_:)))
            bind(panel.useButton, #selector(useWallpaper(_:)))
            bind(panel.pauseButton, #selector(togglePause(_:)))
            bind(panel.stopButton, #selector(stopWallpaper(_:)))
            bind(panel.removeButton, #selector(removeWallpaper(_:)))
            bind(panel.wallpaperPicker, #selector(selectWallpaper(_:)))
            bind(panel.displayPicker, #selector(selectDisplay(_:)))
            bind(panel.qualityPicker, #selector(selectQuality(_:)))
            bind(panel.batteryToggle, #selector(updateEnergy(_:)))
            bind(panel.coveredToggle, #selector(updateEnergy(_:)))
            bind(panel.loginToggle, #selector(updateLogin(_:)))
        }
        evaluate(); preferences?.present()
        if let playbackError { showError(playbackError) }
    }

    private func bind(_ control: NSControl, _ action: Selector) { control.target = self; control.action = action }

    private func save(_ change: (inout AppSettings) -> Void) -> Bool {
        do { try store.update(change); return true }
        catch { showError(error.localizedDescription); return false }
    }

    @objc private func useWallpaper(_ sender: Any?) {
        if save({ $0.enabled = true }) { manuallyPaused = false; playbackError = nil; evaluate() }
    }
    @objc private func stopWallpaper(_ sender: Any?) { if save({ $0.enabled = false }) { evaluate() } }
    @objc private func togglePause(_ sender: Any?) { manuallyPaused.toggle(); playbackError = nil; evaluate() }
    @objc private func toggleBatteryFromMenu(_ sender: Any?) {
        if save({ $0.energy.pauseOnBattery.toggle() }) { evaluate() }
    }
    @objc private func updateEnergy(_ sender: Any?) {
        guard let panel = preferences else { return }
        if save({ $0.energy.pauseOnBattery = panel.batteryToggle.state == .on
            $0.energy.pauseWhenCovered = panel.coveredToggle.state == .on }) { evaluate() }
    }
    @objc private func selectWallpaper(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        if save({ $0.selectedID = id }) { playbackError = nil; evaluate() }
    }
    @objc private func selectDisplay(_ sender: NSPopUpButton) {
        if save({ $0.displayID = sender.selectedItem?.representedObject as? UInt32 }) { evaluate() }
    }
    @objc private func selectQuality(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String, let quality = VideoQuality(rawValue: raw) else { return }
        if save({ $0.importQuality = quality }) { evaluate() }
    }

    @objc private func updateLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { showError("macOS could not change the login item: \(error.localizedDescription)") }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func importVideo(_ sender: Any?) {
        guard !importing else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        picker.allowsMultipleSelection = false; picker.canChooseDirectories = false
        picker.message = "Choose a video loop. Drift keeps an optimized, silent copy on this Mac."
        guard picker.runModal() == .OK, let url = picker.url else { return }
        let quality = store.settings.importQuality
        importing = true; evaluate()
        Task { @MainActor in
            defer { importing = false; evaluate() }
            do {
                let wallpaper = try await VideoImporter.importMovie(from: url, into: store.directory, quality: quality)
                if !save({ $0.imported.append(wallpaper); $0.selectedID = wallpaper.id }) {
                    try? FileManager.default.removeItem(at: store.movieURL(for: wallpaper))
                    try? FileManager.default.removeItem(at: store.posterURL(for: wallpaper))
                } else { playbackError = nil }
            } catch { showError(error.localizedDescription) }
        }
    }

    @objc private func removeWallpaper(_ sender: Any?) {
        let wallpaper = store.selected
        guard !wallpaper.isBuiltIn else { return }
        if save({ $0.imported.removeAll { $0.id == wallpaper.id }; $0.selectedID = Wallpaper.quietCurrent.id }) {
            playbackError = nil; evaluate()
            for url in [store.movieURL(for: wallpaper), store.posterURL(for: wallpaper)] {
                do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
                catch { showError("Removed from your library, but could not move this optimized copy to Trash: \(url.lastPathComponent)") }
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "Drift needs a moment"; alert.informativeText = message
        alert.alertStyle = .warning; alert.addButton(withTitle: "OK"); alert.runModal()
    }

    private func runImportSmokeTest() {
        guard argsContains("--data-directory") else { fputs("IMPORT_SMOKE_FAIL use --data-directory\n", stderr); exit(1) }
        Task { @MainActor in
            do {
                let args = CommandLine.arguments
                let quality = diagnosticQuality()
                var source = store.movieURL(for: .quietCurrent)
                if let index = args.firstIndex(of: "--import-smoke-test"), args.indices.contains(index + 1), !args[index + 1].hasPrefix("--") {
                    source = URL(fileURLWithPath: args[index + 1])
                }
                let sourceAsset = AVURLAsset(url: source)
                guard let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else { throw ImportError.noVideo }
                let sourceSize = try await sourceTrack.load(.naturalSize)
                let sourceTransform = try await sourceTrack.load(.preferredTransform)
                let sourceFPS = try await sourceTrack.load(.nominalFrameRate)
                let oriented = CGRect(origin: .zero, size: sourceSize).applying(sourceTransform)
                guard let plan = VideoImportPlan(sourceWidth: oriented.width, sourceHeight: oriented.height,
                                                sourceFrameRate: Double(sourceFPS), quality: quality) else { throw ImportError.invalidDimensions }
                let wallpaper = try await VideoImporter.importMovie(from: source, into: store.directory, quality: quality)
                let asset = AVURLAsset(url: store.movieURL(for: wallpaper))
                let audioCount = try await asset.loadTracks(withMediaType: .audio).count
                let video = try await asset.loadTracks(withMediaType: .video).first!
                let size = try await video.load(.naturalSize)
                let fps = try await video.load(.nominalFrameRate)
                guard audioCount == 0, abs(size.width - CGFloat(plan.width)) <= 2, abs(size.height - CGFloat(plan.height)) <= 2,
                      abs(Double(fps) - plan.framesPerSecond) <= max(0.1, plan.framesPerSecond * 0.01),
                      FileManager.default.fileExists(atPath: store.posterURL(for: wallpaper).path) else {
                    throw ImportError.exportUnavailable
                }
                print("IMPORT_SMOKE_PASS quality=\(quality.rawValue) \(Int(size.width))x\(Int(size.height)) \(fps)fps audio=\(audioCount)")
                NSApp.terminate(nil)
            } catch { fputs("IMPORT_SMOKE_FAIL \(error)\n", stderr); exit(1) }
        }
    }

    private func runPlaybackSmokeTest() {
        guard let screen else { fputs("SMOKE_FAIL no screen\n", stderr); exit(1) }
        // Isolated test directory is required: never change the user's saved library during this test.
        guard argsContains("--data-directory") else { fputs("SMOKE_FAIL use --data-directory\n", stderr); exit(1) }
        engine.show(posterURL: store.posterURL(for: .quietCurrent), on: screen)
        engine.play(url: diagnosticMovieURL() ?? store.movieURL(for: .quietCurrentSmooth))
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
            guard engine.hasDecoder, engine.hasRenderedFrame else {
                fputs("SMOKE_FAIL no rendered video frame: \(playbackError ?? "unknown error")\n", stderr); exit(1)
            }
            engine.suspend()
            guard !engine.hasDecoder else { fputs("SMOKE_FAIL decoder retained\n", stderr); exit(1) }
            engine.stop()
            guard engine.window == nil else { fputs("SMOKE_FAIL desktop window retained\n", stderr); exit(1) }
            // Keep the run loop alive through repeated close/open cycles to catch window lifetime bugs.
            runWindowCycles(remaining: 8, screen: screen)
        }
    }

    private func diagnosticQuality() -> VideoQuality {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--quality"), args.indices.contains(index + 1) {
            guard let quality = VideoQuality(rawValue: args[index + 1]) else {
                fputs("Unknown --quality. Use eco, balanced, smooth, or ultra.\n", stderr); exit(1)
            }
            return quality
        }
        return store.settings.importQuality
    }

    private func diagnosticMovieURL() -> URL? {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--video"), args.indices.contains(index + 1) {
            return URL(fileURLWithPath: args[index + 1])
        }
        return nil
    }

    private func runWindowCycles(remaining: Int, screen: NSScreen) {
        guard remaining > 0 else {
            print("PLAYBACK_SMOKE_PASS frame rendered; decoder released; 8 desktop window close/open cycles survived")
            NSApp.terminate(nil); return
        }
        engine.show(posterURL: store.posterURL(for: .quietCurrent), on: screen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            engine.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                runWindowCycles(remaining: remaining - 1, screen: screen)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferences(nil); return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}
