import AppKit
import Darwin

enum ProcessSample {
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    static func memory() -> (resident: UInt64, footprint: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (info.resident_size, info.phys_footprint)
    }
}

final class Benchmark {
    private let engine: WallpaperEngine
    private let store: LibraryStore
    private let screen: NSScreen
    private var reports: [[String: Any]] = []

    init(engine: WallpaperEngine, store: LibraryStore, screen: NSScreen) {
        self.engine = engine; self.store = store; self.screen = screen
    }

    func run(completion: @escaping () -> Void) {
        print("BENCHMARK_START · release app only · one built-in 720p/15fps wallpaper"); fflush(stdout)
        measure("wallpaper_off", seconds: 10) { [self] in
            engine.show(posterURL: store.posterURL(for: .quietCurrent), on: screen)
            engine.play(url: store.movieURL(for: .quietCurrent))
            // Let AVFoundation initialize before the steady playback sample.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                measure("playing", seconds: 20) { [self] in
                    engine.suspend()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                        measure("paused_decoder_released", seconds: 10) { [self] in
                            engine.stop()
                            let report: [String: Any] = ["samples": reports,
                                "scope": "Drift process CPU and memory only; excludes GPU, WindowServer, and system decoder services.",
                                "media": "Quiet Current, 1280x720 H.264, 15 fps",
                                "macOS": ProcessInfo.processInfo.operatingSystemVersionString]
                            let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                            print("BENCHMARK_JSON\n" + String(decoding: data, as: UTF8.self)); fflush(stdout)
                            completion()
                        }
                    }
                }
            }
        }
    }

    private func measure(_ phase: String, seconds: Double, completion: @escaping () -> Void) {
        print("BENCHMARK_PHASE \(phase)"); fflush(stdout)
        let cpuStart = ProcessSample.cpuSeconds(), start = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let cpu = (ProcessSample.cpuSeconds() - cpuStart) / elapsed * 100
            let memory = ProcessSample.memory()
            reports.append(["phase": phase, "seconds": elapsed, "cpu_percent_one_core": cpu,
                "resident_mb": Double(memory.resident) / 1_048_576,
                "physical_footprint_mb": Double(memory.footprint) / 1_048_576,
                "decoder_present": engine.hasDecoder, "frame_rendered": engine.hasRenderedFrame])
            completion()
        }
    }
}
