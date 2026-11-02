import AppKit
import ServiceManagement
import DriftCore

private extension NSColor {
    static let driftMint = NSColor(srgbRed: 0.53, green: 0.88, blue: 0.78, alpha: 1)
}

final class PosterPreview: NSView {
    private let imageLayer = CALayer()
    private let shade = CAGradientLayer()
    let titleLabel = NSTextField(labelWithString: "Quiet Current")
    private let caption = NSTextField(labelWithString: "A little motion. Room to breathe.")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14; layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        layer?.addSublayer(imageLayer)
        shade.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.65).cgColor]
        shade.startPoint = CGPoint(x: 0.5, y: 0.9); shade.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(shade)
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold); titleLabel.textColor = .white
        caption.font = .systemFont(ofSize: 12); caption.textColor = NSColor.white.withAlphaComponent(0.75)
        for label in [titleLabel, caption] { addSubview(label); label.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            titleLabel.bottomAnchor.constraint(equalTo: caption.topAnchor, constant: -5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -22),
            caption.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.frame = bounds; shade.frame = bounds
        CATransaction.commit()
    }
    func show(image: NSImage?, title: String) {
        imageLayer.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        titleLabel.stringValue = title
    }
}

final class PreferencesWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    let preview = PosterPreview(frame: .zero)
    let wallpaperPicker = NSPopUpButton()
    let displayPicker = NSPopUpButton()
    let qualityPicker = NSPopUpButton()
    let qualityDescription = NSTextField(wrappingLabelWithString: "")
    let detailLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "Ready when you are")
    let importButton = NSButton(title: "Import video…", target: nil, action: nil)
    let useButton = NSButton(title: "Use wallpaper", target: nil, action: nil)
    let pauseButton = NSButton(title: "Pause", target: nil, action: nil)
    let stopButton = NSButton(title: "Turn off", target: nil, action: nil)
    let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    let batteryToggle = NSButton(checkboxWithTitle: "Pause on battery power", target: nil, action: nil)
    let coveredToggle = NSButton(checkboxWithTitle: "Pause when the desktop is covered", target: nil, action: nil)
    let loginToggle = NSButton(checkboxWithTitle: "Open Drift at login", target: nil, action: nil)
    let progress = NSProgressIndicator()
    private var displayedPosterID: String?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 744, height: 764),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Drift"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.055, green: 0.075, blue: 0.09, alpha: 1)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        build(in: window.contentView!)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func text(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color
        return label
    }

    private func row(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .horizontal
        stack.spacing = spacing; stack.alignment = .centerY
        return stack
    }

    private func build(in root: NSView) {
        let title = text("Drift", size: 30, weight: .bold)
        let wave = NSImageView(image: NSImage(systemSymbolName: "water.waves", accessibilityDescription: "Drift")!)
        wave.contentTintColor = .driftMint
        wave.translatesAutoresizingMaskIntoConstraints = false
        wave.widthAnchor.constraint(equalToConstant: 42).isActive = true
        wave.heightAnchor.constraint(equalToConstant: 42).isActive = true
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let badge = text("●  ECO BY DEFAULT", size: 10, weight: .semibold, color: .driftMint)
        let heading = row([wave, title, spacer, badge], spacing: 12)
        let subtitle = text("Live wallpapers with a lighter footprint.", size: 13, color: .secondaryLabelColor)
        let top = NSStackView(views: [heading, subtitle]); top.orientation = .vertical; top.alignment = .leading; top.spacing = 6
        heading.widthAnchor.constraint(equalTo: top.widthAnchor).isActive = true

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: 212).isActive = true
        wallpaperPicker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        wallpaperPicker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wallpaperPicker.setAccessibilityLabel("Wallpaper")
        for button in [importButton, useButton, pauseButton, stopButton, removeButton] {
            button.bezelStyle = .rounded; button.controlSize = .regular
        }
        useButton.bezelColor = NSColor(srgbRed: 0.23, green: 0.54, blue: 0.46, alpha: 1)
        useButton.keyEquivalent = "\r"
        let selection = row([wallpaperPicker, importButton, removeButton])
        qualityPicker.setAccessibilityLabel("Import quality")
        for quality in VideoQuality.allCases {
            qualityPicker.addItem(withTitle: quality.title)
            qualityPicker.lastItem?.representedObject = quality.rawValue
        }
        qualityPicker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let qualityRow = row([text("Import quality", size: 12, color: .secondaryLabelColor), qualityPicker])
        qualityDescription.font = .systemFont(ofSize: 11)
        qualityDescription.textColor = .secondaryLabelColor
        detailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12); statusLabel.textColor = .driftMint
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        let actions = row([useButton, pauseButton, stopButton, progress, statusLabel], spacing: 12)
        let separator = NSBox(); separator.boxType = .separator
        let savingsTitle = text("Made to give your Mac room.", size: 15, weight: .semibold)
        let savingsDetail = text("One display. Small videos. No sound. A still image whenever playback pauses.", size: 11, color: .secondaryLabelColor)
        displayPicker.setAccessibilityLabel("Wallpaper display")
        displayPicker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let displayRow = row([text("Display", size: 12, color: .secondaryLabelColor), displayPicker])
        loginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let protections = text("Always rests during Low Power Mode, heat, memory pressure, low battery, screen lock, and sleep.", size: 11, color: .secondaryLabelColor)
        let local = text("Quality applies to new imports. Reimport the original to improve an existing wallpaper.", size: 11, color: .tertiaryLabelColor)
        let stack = NSStackView(views: [top, preview, selection, detailLabel, qualityRow, qualityDescription, actions, separator, savingsTitle,
                                        savingsDetail, displayRow, batteryToggle, coveredToggle, loginToggle, protections, local])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.setCustomSpacing(18, after: top)
        stack.setCustomSpacing(16, after: actions)
        stack.setCustomSpacing(14, after: separator)
        root.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -22)
        ])
        for view in [top, preview, selection, qualityRow, actions, separator, displayRow] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for view in [subtitle, qualityDescription, savingsDetail, protections, local] {
            view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        }
    }

    func refresh(store: LibraryStore, status: String, manuallyPaused: Bool, importing: Bool) {
        let selected = store.selected
        if displayedPosterID != selected.id {
            preview.show(image: NSImage(contentsOf: store.posterURL(for: selected)), title: selected.title)
            displayedPosterID = selected.id
        }
        if wallpaperPicker.itemTitles != store.wallpapers.map(\.title) {
            wallpaperPicker.removeAllItems()
            for wallpaper in store.wallpapers {
                wallpaperPicker.addItem(withTitle: wallpaper.title)
                wallpaperPicker.lastItem?.representedObject = wallpaper.id
            }
        }
        if let index = store.wallpapers.firstIndex(where: { $0.id == selected.id }) { wallpaperPicker.selectItem(at: index) }
        detailLabel.stringValue = selected.detail
        statusLabel.stringValue = status
        pauseButton.title = manuallyPaused ? "Resume" : "Pause"
        pauseButton.isEnabled = store.settings.enabled && !importing
        stopButton.isEnabled = store.settings.enabled
        useButton.title = store.settings.enabled ? "Wallpaper on" : "Use wallpaper"
        useButton.isEnabled = !store.settings.enabled && !importing
        importButton.isEnabled = !importing
        wallpaperPicker.isEnabled = !importing
        qualityPicker.isEnabled = !importing
        if let item = qualityPicker.itemArray.first(where: { $0.representedObject as? String == store.settings.importQuality.rawValue }) {
            qualityPicker.select(item)
        }
        qualityDescription.stringValue = store.settings.importQuality.explanation
        removeButton.isEnabled = !selected.isBuiltIn && !importing
        batteryToggle.state = store.settings.energy.pauseOnBattery ? .on : .off
        coveredToggle.state = store.settings.energy.pauseWhenCovered ? .on : .off
        if importing { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        refreshDisplays(selectedID: store.settings.displayID)
    }

    func refreshDisplays(selectedID: UInt32?) {
        displayPicker.removeAllItems()
        displayPicker.addItem(withTitle: "Built-in display (or main display)")
        for screen in NSScreen.screens {
            displayPicker.addItem(withTitle: screen.localizedName)
            displayPicker.lastItem?.representedObject = screen.displayID
            if screen.displayID == selectedID { displayPicker.select(displayPicker.lastItem) }
        }
    }

    func present() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onClose?()
    }
}

extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
