import AppKit
import AVFoundation
import DriftCore

struct Wallpaper: Codable, Equatable {
    var id: String
    var title: String
    var filename: String
    var posterFilename: String
    var width: Int
    var height: Int
    var framesPerSecond: Double
    var duration: Double
    var isBuiltIn: Bool = false

    static let quietCurrent = Wallpaper(
        id: "quiet-current", title: "Quiet Current", filename: "quiet-current.mp4",
        posterFilename: "quiet-current.png", width: 1280, height: 720, framesPerSecond: 15, duration: 12,
        isBuiltIn: true
    )
    static let quietCurrentSmooth = Wallpaper(
        id: "quiet-current-smooth", title: "Quiet Current · Smooth", filename: "quiet-current-1080p60.mp4",
        posterFilename: "quiet-current.png", width: 1920, height: 1080, framesPerSecond: 60, duration: 12,
        isBuiltIn: true
    )
    var detail: String {
        let fps = abs(framesPerSecond - framesPerSecond.rounded()) < 0.005
            ? String(format: "%.0f", framesPerSecond) : String(format: "%.2f", framesPerSecond)
        return "\(width) × \(height)  ·  \(fps) fps  ·  silent loop"
    }
}

struct AppSettings: Codable {
    var energy = EnergyPreferences()
    var enabled = false
    var selectedID = Wallpaper.quietCurrent.id
    var displayID: UInt32?
    var imported: [Wallpaper] = []
    var importQuality = VideoQuality.eco

    init() {}

    private enum CodingKeys: String, CodingKey {
        case energy, enabled, selectedID, displayID, imported, importQuality
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        energy = try values.decodeIfPresent(EnergyPreferences.self, forKey: .energy) ?? EnergyPreferences()
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        selectedID = try values.decodeIfPresent(String.self, forKey: .selectedID) ?? Wallpaper.quietCurrent.id
        displayID = try values.decodeIfPresent(UInt32.self, forKey: .displayID)
        imported = try values.decodeIfPresent([Wallpaper].self, forKey: .imported) ?? []
        importQuality = try values.decodeIfPresent(VideoQuality.self, forKey: .importQuality) ?? .eco
    }
}

final class LibraryStore {
    let directory: URL
    private(set) var settings: AppSettings
    private var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    var wallpapers: [Wallpaper] { [.quietCurrent, .quietCurrentSmooth] + settings.imported }
    var selected: Wallpaper { wallpapers.first { $0.id == settings.selectedID } ?? .quietCurrent }

    init(directory: URL? = nil) throws {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Drift", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let file = self.directory.appendingPathComponent("settings.json")
        if FileManager.default.fileExists(atPath: file.path) {
            // Preserve an unreadable library instead of silently replacing it.
            settings = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: file))
        } else {
            settings = AppSettings()
        }
    }

    func update(_ change: (inout AppSettings) -> Void) throws {
        var next = settings
        change(&next)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: settingsURL, options: .atomic)
        settings = next
    }

    func movieURL(for wallpaper: Wallpaper) -> URL {
        wallpaper.isBuiltIn ? resource(wallpaper.filename) : directory.appendingPathComponent(wallpaper.filename)
    }

    func posterURL(for wallpaper: Wallpaper) -> URL {
        wallpaper.isBuiltIn ? resource(wallpaper.posterFilename) : directory.appendingPathComponent(wallpaper.posterFilename)
    }

    private func resource(_ filename: String) -> URL {
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("Wallpapers").appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        return Bundle.module.resourceURL!.appendingPathComponent(filename)
    }
}

enum ImportError: LocalizedError {
    case noVideo, invalidDuration, invalidDimensions, exportUnavailable, failedExport(String)
    var errorDescription: String? {
        switch self {
        case .noVideo: return "Choose a local video file with a playable video track."
        case .invalidDuration: return "Choose a video between one second and five minutes long. Short loops use less storage."
        case .invalidDimensions: return "This video has invalid frame dimensions. Try exporting it as a standard MP4."
        case .exportUnavailable: return "macOS could not prepare this video. Try an MP4 or MOV file."
        case .failedExport(let reason): return "Could not optimize the video: \(reason)"
        }
    }
}

enum VideoImporter {
    /// One import at a time. Only a video track is copied; audio never reaches the library.
    static func importMovie(from source: URL, into directory: URL, quality: VideoQuality = .eco) async throws -> Wallpaper {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw ImportError.noVideo }
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, (1...300).contains(duration.seconds) else { throw ImportError.invalidDuration }
        let size = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let frameRate = try await video.load(.nominalFrameRate)
        let oriented = CGRect(origin: .zero, size: size).applying(transform)
        guard let plan = VideoImportPlan(sourceWidth: oriented.width, sourceHeight: oriented.height,
                                        sourceFrameRate: Double(frameRate), quality: quality) else {
            throw ImportError.invalidDimensions
        }
        let width = plan.width, height = plan.height

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ImportError.exportUnavailable
        }
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: video, at: .zero)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: width, height: height)
        videoComposition.frameDuration = CMTime(seconds: 1 / plan.framesPerSecond, preferredTimescale: 600_000)
        guard videoComposition.frameDuration.isNumeric, videoComposition.frameDuration.value > 0 else {
            throw ImportError.exportUnavailable
        }
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let normalized = transform.concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
            .concatenating(CGAffineTransform(scaleX: CGFloat(width) / oriented.width, y: CGFloat(height) / oriented.height))
        layer.setTransform(normalized, at: .zero)
        instruction.layerInstructions = [layer]
        videoComposition.instructions = [instruction]

        let id = UUID().uuidString.lowercased()
        let filename = "\(id).mp4", posterFilename = "\(id).png"
        let movieURL = directory.appendingPathComponent(filename)
        let posterURL = directory.appendingPathComponent(posterFilename)
        var finished = false
        defer {
            if !finished {
                try? FileManager.default.removeItem(at: movieURL)
                try? FileManager.default.removeItem(at: posterURL)
            }
        }
        let preset: String
        switch quality {
        case .eco: preset = AVAssetExportPreset1280x720
        case .balanced, .smooth: preset = AVAssetExportPreset1920x1080
        case .ultra: preset = AVAssetExportPresetHEVC3840x2160
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw ImportError.exportUnavailable
        }
        exporter.videoComposition = videoComposition
        exporter.outputURL = movieURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else {
            throw ImportError.failedExport(exporter.error?.localizedDescription ?? "The export was interrupted.")
        }
        let exportedAsset = AVURLAsset(url: movieURL)
        guard let exportedTrack = try await exportedAsset.loadTracks(withMediaType: .video).first else { throw ImportError.noVideo }
        let exportedSize = try await exportedTrack.load(.naturalSize)
        let exportedFPS = Double(try await exportedTrack.load(.nominalFrameRate))
        guard exportedSize.width <= CGFloat(quality.maximumWidth), exportedSize.height <= CGFloat(quality.maximumHeight),
              exportedFPS.isFinite, exportedFPS > 0,
              abs(exportedFPS - plan.framesPerSecond) <= max(0.1, plan.framesPerSecond * 0.01) else {
            throw ImportError.failedExport("macOS did not preserve the selected resolution or frame rate.")
        }
        let generator = AVAssetImageGenerator(asset: exportedAsset)
        generator.appliesPreferredTrackTransform = true
        switch quality {
        case .eco: generator.maximumSize = CGSize(width: 640, height: 360)
        case .balanced, .smooth: generator.maximumSize = CGSize(width: 1280, height: 720)
        case .ultra: generator.maximumSize = CGSize(width: 1920, height: 1080)
        }
        let (image, _) = try await generator.image(at: .zero)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ImportError.exportUnavailable
        }
        try png.write(to: posterURL, options: .atomic)
        finished = true
        return Wallpaper(id: id, title: source.deletingPathExtension().lastPathComponent,
                         filename: filename, posterFilename: posterFilename,
                         width: Int(exportedSize.width), height: Int(exportedSize.height), framesPerSecond: exportedFPS, duration: duration.seconds)
    }
}
