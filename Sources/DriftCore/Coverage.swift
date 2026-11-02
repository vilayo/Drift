import Foundation

public struct DesktopRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public enum DesktopCoverage {
    /// Exact union area: overlapping windows must not count the same pixels twice.
    public static func fraction(of screen: DesktopRect, coveredBy windows: [DesktopRect]) -> Double {
        guard screen.width > 0, screen.height > 0 else { return 0 }
        let clipped = windows.compactMap { window -> DesktopRect? in
            let x = max(screen.x, window.x), y = max(screen.y, window.y)
            let right = min(screen.x + screen.width, window.x + window.width)
            let top = min(screen.y + screen.height, window.y + window.height)
            guard right > x, top > y else { return nil }
            return DesktopRect(x: x, y: y, width: right - x, height: top - y)
        }
        let edges = Array(Set(clipped.flatMap { [$0.x, $0.x + $0.width] })).sorted()
        guard edges.count > 1 else { return 0 }
        var area = 0.0
        for index in 0..<(edges.count - 1) {
            let left = edges[index], right = edges[index + 1]
            let intervals = clipped.filter { $0.x < right && $0.x + $0.width > left }
                .map { ($0.y, $0.y + $0.height) }.sorted { $0.0 < $1.0 }
            var mergedLength = 0.0
            var end = -Double.infinity
            for (start, stop) in intervals {
                mergedLength += max(0, stop - max(start, end))
                end = max(end, stop)
            }
            area += (right - left) * mergedLength
        }
        return min(1, max(0, area / (screen.width * screen.height)))
    }
}
