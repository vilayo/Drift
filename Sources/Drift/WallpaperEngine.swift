import AppKit
import AVFoundation
import DriftCore

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class WallpaperSurface: NSView {
    let posterLayer = CALayer()
    let videoLayer = AVPlayerLayer()

    init(poster: NSImage?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        if let poster { posterLayer.contents = poster.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        posterLayer.contentsGravity = .resizeAspectFill
        posterLayer.masksToBounds = true
        videoLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(posterLayer)
        layer?.addSublayer(videoLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        posterLayer.frame = bounds; videoLayer.frame = bounds
        CATransaction.commit()
    }
}

final class WallpaperEngine {
    private(set) var window: DesktopWindow?
    private var surface: WallpaperSurface?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var failureObservation: NSKeyValueObservation?
    private var readinessObservation: NSKeyValueObservation?
    private var itemChangeObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var currentURL: URL?
    private var resumeTime = CMTime.zero
    var onError: ((String) -> Void)?
    var hasDecoder: Bool { player != nil }
    var hasRenderedFrame: Bool { surface?.videoLayer.isReadyForDisplay ?? false }

    func show(posterURL: URL, on screen: NSScreen) {
        stop()
        let window = DesktopWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        window.hasShadow = false
        // Swift owns this window. NSWindow.close() must not release it a second time.
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.isOpaque = true
        window.backgroundColor = .black
        let surface = WallpaperSurface(poster: NSImage(contentsOf: posterURL))
        window.contentView = surface
        window.orderFrontRegardless()
        self.window = window; self.surface = surface
    }

    func play(url: URL) {
        guard player == nil, let surface else { return }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            onError?("This wallpaper's video file is missing. Choose another wallpaper or import it again.")
            return
        }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 1
        item.preferredPeakBitRate = 3_000_000
        item.preferredMaximumResolution = CGSize(width: 1280, height: 720)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        queue.preventsDisplaySleepDuringVideoPlayback = false
        queue.allowsExternalPlayback = false
        let looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue; self.looper = looper; currentURL = url
        surface.videoLayer.player = queue
        surface.videoLayer.isHidden = true
        readinessObservation = surface.videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak surface] layer, _ in
            DispatchQueue.main.async { surface?.videoLayer.isHidden = !layer.isReadyForDisplay }
        }
        failureObservation = looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
            if looper.status == .failed {
                let message = looper.error?.localizedDescription ?? "macOS could not play this wallpaper."
                DispatchQueue.main.async { self?.onError?(message) }
            }
        }
        itemChangeObservation = queue.observe(\.currentItem, options: [.initial, .new]) { [weak self] queue, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.player === queue else { return }
                self.itemStatusObservation = queue.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    if item.status == .failed {
                        let message = item.error?.localizedDescription ?? "macOS could not decode this video."
                        DispatchQueue.main.async { self?.onError?(message) }
                    }
                }
            }
        }
        if resumeTime.isValid && resumeTime.seconds > 0 { queue.seek(to: resumeTime) }
        queue.play()
    }

    /// Release AVFoundation's queue and decoder surfaces, keeping only a small static poster.
    func suspend() {
        if let player { resumeTime = player.currentTime() }
        player?.pause()
        readinessObservation = nil; failureObservation = nil
        itemStatusObservation = nil; itemChangeObservation = nil
        surface?.videoLayer.isHidden = true
        surface?.videoLayer.player = nil
        looper?.disableLooping()
        player?.removeAllItems()
        looper = nil; player = nil
    }

    func stop() {
        suspend()
        resumeTime = .zero; currentURL = nil
        window?.orderOut(nil)
        window?.close()
        window = nil; surface = nil
    }
}
