// Original, deterministic artwork. Regenerates the bundled wallpaper without any downloads.
import AppKit
import AVFoundation

let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sources/Drift/Resources")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let width = 1280, height = 720, fps: Int32 = 15, frames = 180
let colorspace = CGColorSpaceCreateDeviceRGB()

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorspace, components: [r, g, b, a])!
}

func draw(_ context: CGContext, phase: Double) {
    let w = CGFloat(width), h = CGFloat(height)
    let background = CGGradient(colorsSpace: colorspace,
        colors: [color(0.025, 0.08, 0.15), color(0.07, 0.23, 0.28), color(0.17, 0.40, 0.39)] as CFArray,
        locations: [0, 0.62, 1])!
    context.drawLinearGradient(background, start: .zero, end: CGPoint(x: w, y: h), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Wide, overlapping ribbons move on a seamless 12-second cycle.
    for band in stride(from: 6, through: 0, by: -1) {
        let b = CGFloat(band)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: w, y: 0))
        for step in stride(from: 64, through: 0, by: -1) {
            let x = CGFloat(step) / 64 * w
            let curve = sin(Double(x / w) * 3.8 + phase + Double(b) * 0.44)
            let second = cos(Double(x / w) * 2.0 - phase + Double(b) * 0.5)
            let y = h * (0.20 + b * 0.075) + CGFloat(curve) * h * 0.09 + CGFloat(second) * h * 0.07
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        context.saveGState(); context.addPath(path); context.clip()
        let gradient = CGGradient(colorsSpace: colorspace,
            colors: [color(0.03 + b * 0.009, 0.11 + b * 0.029, 0.18 + b * 0.026),
                     color(0.08 + b * 0.024, 0.28 + b * 0.045, 0.31 + b * 0.037)] as CFArray,
            locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: w * 0.2, y: 0), end: CGPoint(x: w, y: h), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
}

let url = destination.appendingPathComponent("quiet-current.mp4")
if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 900_000,
        AVVideoMaxKeyFrameIntervalKey: 30, AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoAllowFrameReorderingKey: false]
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
])
writer.add(input)
guard writer.startWriting() else { fatalError(writer.error!.localizedDescription) }
writer.startSession(atSourceTime: .zero)
for index in 0..<frames {
    while !input.isReadyForMoreMediaData {
        if writer.status == .failed { fatalError(writer.error!.localizedDescription) }
        Thread.sleep(forTimeInterval: 0.003)
    }
    try autoreleasepool {
        var maybeBuffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer) == kCVReturnSuccess,
              let buffer = maybeBuffer else { fatalError("Could not allocate a video frame") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorspace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        draw(context, phase: Double(index) / Double(frames) * .pi * 2)
        if index == 0, let image = context.makeImage() {
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: destination.appendingPathComponent("quiet-current.png"))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: fps)) else {
            fatalError(writer.error?.localizedDescription ?? "Could not append a video frame")
        }
    }
}
input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
guard writer.status == .completed else { fatalError(writer.error?.localizedDescription ?? "Could not finish the video") }
print("Generated Quiet Current: 1280x720, 15 fps, 12 seconds")
