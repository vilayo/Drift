import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (points, scale) in sizes {
    let size = points * scale, s = CGFloat(size)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let bounds = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let rounded = NSBezierPath(roundedRect: bounds, xRadius: s * 0.19, yRadius: s * 0.19)
    NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.22, blue: 0.28, alpha: 1),
               ending: NSColor(srgbRed: 0.04, green: 0.11, blue: 0.18, alpha: 1))!.draw(in: rounded, angle: -90)
    rounded.addClip()
    for index in 0..<3 {
        let y = s * (0.35 + CGFloat(index) * 0.14)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: s * 0.23, y: y))
        path.curve(to: NSPoint(x: s * 0.77, y: y),
            controlPoint1: NSPoint(x: s * 0.43, y: y + s * 0.16),
            controlPoint2: NSPoint(x: s * 0.57, y: y - s * 0.16))
        path.lineWidth = s * 0.043; path.lineCapStyle = .round
        NSColor(srgbRed: 0.55, green: 0.9, blue: 0.8, alpha: 1 - CGFloat(index) * 0.2).setStroke(); path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
