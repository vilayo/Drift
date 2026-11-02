import AppKit
import DriftCore
import IOKit.ps

final class SystemMonitor {
    var onChange: (() -> Void)?
    private(set) var conditions = PlaybackConditions()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var systemObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var powerSource: CFRunLoopSource?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var coverageTimer: Timer?
    var targetScreen: (() -> NSScreen?)?

    init() {
        let info = ProcessInfo.processInfo
        _ = info.thermalState
        refreshPower()
        conditions.lowPower = info.isLowPowerModeEnabled
        conditions.hot = info.thermalState == .serious || info.thermalState == .critical
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            conditions.locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, .init(NSWorkspace.screensDidSleepNotification.rawValue)) { $0.conditions.sleeping = true }
        observe(workspace, .init(NSWorkspace.screensDidWakeNotification.rawValue)) { $0.conditions.sleeping = false }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.conditions.sleeping = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.conditions.sleeping = false; $0.refreshPower() }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observe(workspace, name) { if $0.coverageTimer != nil { $0.refreshCoverage() } }
        }
        let center = NotificationCenter.default
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            systemObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.conditions.lowPower = info.isLowPowerModeEnabled
                self.conditions.hot = info.thermalState == .serious || info.thermalState == .critical
                self.refreshPower(); self.onChange?()
            })
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedObservers.append(distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                self?.conditions.locked = locked; self?.onChange?()
            })
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let unmanaged = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.refreshPower(); monitor.onChange?()
        }, context) {
            powerSource = unmanaged.takeRetainedValue()
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes)
        }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical, .normal], queue: .main)
        pressure.setEventHandler { [weak self, weak pressure] in
            guard let self, let pressure else { return }
            self.conditions.memoryPressure = pressure.data.contains(.warning) || pressure.data.contains(.critical)
            self.onChange?()
        }
        pressure.resume(); pressureSource = pressure
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, change: @escaping (SystemMonitor) -> Void) {
        workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; change(self); self.onChange?()
        })
    }

    func refreshPower() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        conditions.onBattery = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSBatteryPowerValue
        conditions.batteryPercent = nil
        if let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let item = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      let current = item[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = item[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                if item[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                    conditions.batteryPercent = current * 100 / maximum; break
                }
            }
        }
    }

    func monitorCoverage(_ enabled: Bool) {
        guard enabled != (coverageTimer != nil) else { return }
        if enabled {
            refreshCoverage()
            let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                guard let self else { return }
                let before = self.conditions.desktopCovered
                self.refreshCoverage()
                if before != self.conditions.desktopCovered { self.onChange?() }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common); coverageTimer = timer
        } else {
            coverageTimer?.invalidate(); coverageTimer = nil; conditions.desktopCovered = false
        }
    }

    func refreshCoverage() {
        guard let screen = targetScreen?(),
              let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return }
        // Quartz is top-left based; AppKit screen coordinates are bottom-left based.
        let primaryTop = primary.frame.maxY
        let useful = screen.visibleFrame
        let rect = DesktopRect(x: useful.minX, y: primaryTop - useful.maxY, width: useful.width, height: useful.height)
        let windows = rows.prefix(256).compactMap { row -> DesktopRect? in
            guard (row[kCGWindowLayer as String] as? Int) == 0,
                  (row[kCGWindowOwnerPID as String] as? Int32) != ProcessInfo.processInfo.processIdentifier,
                  (row[kCGWindowAlpha as String] as? Double ?? 1) >= 0.98,
                  let data = row[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: data) else { return nil }
            return DesktopRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
        }
        conditions.desktopCovered = DesktopCoverage.fraction(of: rect, coveredBy: windows) >= 0.98
    }

    deinit {
        coverageTimer?.invalidate(); pressureSource?.cancel()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        systemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }
}
