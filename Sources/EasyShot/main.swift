import AppKit
import ServiceManagement

// MARK: - Configuration

private enum Config {
    static let maxThumbWidth: CGFloat = 280
    static let maxThumbHeight: CGFloat = 200
    static let padding: CGFloat = 8
    static let cornerRadius: CGFloat = 10
    static let closeButtonSize: CGFloat = 22
    static let screenMargin: CGFloat = 20
    static let peekHeight: CGFloat = 35
}

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let stackManager = ThumbnailStackManager()
    private var watcher: ScreenshotWatcher!

    func applicationDidFinishLaunching(_ notification: Notification) {
        disableMacOSScreenshotThumbnail()
        registerLoginItem()
        setupMenuBar()

        watcher = ScreenshotWatcher { [weak self] url in
            self?.stackManager.addScreenshot(at: url)
        }
        watcher.start()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.stackManager.relayout()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder",
                                   accessibilityDescription: "EasyShot")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "About EasyShot", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(withTitle: "Clear All", action: #selector(clearAll), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit EasyShot", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "EasyShot",
            .applicationVersion: "1.0",
            .credits: NSAttributedString(
                string: "by Skelpo GmbH",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]),
        ])
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            sender.state = .off
        } else {
            try? SMAppService.mainApp.register()
            sender.state = .on
        }
    }

    private func registerLoginItem() {
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    private func disableMacOSScreenshotThumbnail() {
        // Check if already disabled
        let readProc = Process()
        readProc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        readProc.arguments = ["read", "com.apple.screencapture", "show-thumbnail"]
        let readPipe = Pipe()
        readProc.standardOutput = readPipe
        readProc.standardError = Pipe()

        if let _ = try? readProc.run() {
            readProc.waitUntilExit()
            let data = readPipe.fileHandleForReading.readDataToEndOfFile()
            let val = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if val == "0" { return }
        }

        // Disable the macOS floating screenshot thumbnail
        let writeProc = Process()
        writeProc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        writeProc.arguments = [
            "write", "com.apple.screencapture", "show-thumbnail", "-bool", "false",
        ]
        writeProc.standardOutput = Pipe()
        writeProc.standardError = Pipe()
        try? writeProc.run()
        writeProc.waitUntilExit()

        // Restart SystemUIServer to apply
        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killProc.arguments = ["SystemUIServer"]
        killProc.standardOutput = Pipe()
        killProc.standardError = Pipe()
        try? killProc.run()
        killProc.waitUntilExit()
    }

    @objc private func clearAll() { stackManager.clearAll() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - ScreenshotWatcher

class ScreenshotWatcher {
    private let onChange: (URL) -> Void
    private var knownFiles = Set<String>()
    private var source: DispatchSourceFileSystemObject?
    private let directory: URL

    init(onChange: @escaping (URL) -> Void) {
        self.onChange = onChange
        self.directory = Self.screenshotDirectory()
    }

    func start() {
        knownFiles = scanFiles()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("EasyShot: Failed to open screenshot directory: \(directory.path)")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.handleChange() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        NSLog("EasyShot: Watching \(directory.path)")
    }

    private func handleChange() {
        let current = scanFiles()
        let added = current.subtracting(knownFiles)
        knownFiles = current

        for name in added.sorted() {
            let url = directory.appendingPathComponent(name)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onChange(url)
            }
        }
    }

    private func scanFiles() -> Set<String> {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return Set(items.filter(Self.isScreenshot))
    }

    private static func isScreenshot(_ name: String) -> Bool {
        let lower = name.lowercased()
        let isImage = lower.hasSuffix(".png") || lower.hasSuffix(".jpg")
            || lower.hasSuffix(".jpeg") || lower.hasSuffix(".tiff")
        let isScreenshot = lower.hasPrefix("screenshot") || lower.hasPrefix("screen shot")
            || lower.contains("\u{622A}\u{5C4F}")
            || lower.contains(
                "\u{30B9}\u{30AF}\u{30EA}\u{30FC}\u{30F3}\u{30B7}\u{30E7}\u{30C3}\u{30C8}")
            || lower.hasPrefix("bildschirmfoto")
        return isImage && isScreenshot
    }

    static func screenshotDirectory() -> URL {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        proc.arguments = ["read", "com.apple.screencapture", "location"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        if let _ = try? proc.run() {
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !path.isEmpty
                {
                    let expanded = NSString(string: path).expandingTildeInPath
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir),
                        isDir.boolValue
                    {
                        return URL(fileURLWithPath: expanded)
                    }
                }
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }
}

// MARK: - ThumbnailStackManager

class ThumbnailStackManager {
    private var panels = [ThumbnailPanel]()

    func addScreenshot(at url: URL, retries: Int = 4) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let image = NSImage(contentsOf: url), image.isValid else {
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.addScreenshot(at: url, retries: retries - 1)
                }
            }
            return
        }

        let panel = ThumbnailPanel(url: url, image: image) { [weak self] p in
            self?.remove(p)
        }
        panels.append(panel)
        layout(animated: true)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 1
        }
    }

    func remove(_ panel: ThumbnailPanel) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panels.removeAll { $0 === panel }
            self?.layout(animated: true)
        })
    }

    func clearAll() {
        let copy = panels
        panels.removeAll()
        for p in copy {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                p.animator().alphaValue = 0
            }, completionHandler: {
                p.orderOut(nil)
            })
        }
    }

    func relayout() {
        layout(animated: false)
    }

    private func layout(animated: Bool) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame

        // Shrink peek if too many items to fit on screen
        let newestHeight = panels.last?.frame.height ?? 200
        let maxAvailable = visible.height - Config.screenMargin * 2 - newestHeight
        let effectivePeek: CGFloat =
            panels.count > 1
            ? min(Config.peekHeight, max(10, maxAvailable / CGFloat(panels.count - 1)))
            : 0

        // Oldest panels sit higher (peek out above), newest at the base
        for (index, panel) in panels.enumerated() {
            let distFromNewest = panels.count - 1 - index
            let x = visible.maxX - panel.frame.width - Config.screenMargin
            let y = visible.minY + Config.screenMargin + CGFloat(distFromNewest) * effectivePeek
            let origin = NSPoint(x: x, y: y)

            if animated && panel.isVisible {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrameOrigin(origin)
                }
            } else {
                panel.setFrameOrigin(origin)
            }
        }

        // Z-ordering: oldest first, newest last (in front)
        for panel in panels {
            panel.orderFrontRegardless()
        }

        // Badge on the newest (front) panel only
        for (index, panel) in panels.enumerated() {
            panel.badgeCount = (index == panels.count - 1 && panels.count > 1)
                ? panels.count : 0
        }
    }
}

// MARK: - ThumbnailPanel

class ThumbnailPanel: NSPanel {
    let screenshotURL: URL
    private let onDismiss: (ThumbnailPanel) -> Void

    var badgeCount: Int = 0 {
        didSet { (contentView as? ThumbnailView)?.badgeCount = badgeCount }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(url: URL, image: NSImage, onDismiss: @escaping (ThumbnailPanel) -> Void) {
        self.screenshotURL = url
        self.onDismiss = onDismiss

        let imgSize = image.size
        let scale = min(Config.maxThumbWidth / imgSize.width,
                        Config.maxThumbHeight / imgSize.height, 1.0)
        let w = imgSize.width * scale + Config.padding * 2
        let h = imgSize.height * scale + Config.padding * 2

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false

        let thumbView = ThumbnailView(
            frame: NSRect(x: 0, y: 0, width: w, height: h),
            image: image, url: url,
            onClose: { [weak self] in
                guard let self = self else { return }
                self.onDismiss(self)
            },
            onDrop: { [weak self] in
                guard let self = self else { return }
                self.onDismiss(self)
            })
        contentView = thumbView
    }
}

// MARK: - ThumbnailView

class ThumbnailView: NSView, NSDraggingSource {
    private let image: NSImage
    private let fileURL: URL
    private let onClose: () -> Void
    private let onDrop: () -> Void
    private var hovering = false
    private var dragOrigin: NSPoint?
    private let closeBtnRect: NSRect

    var badgeCount: Int = 0 {
        didSet { needsDisplay = true }
    }

    init(frame: NSRect, image: NSImage, url: URL,
         onClose: @escaping () -> Void, onDrop: @escaping () -> Void)
    {
        self.image = image
        self.fileURL = url
        self.onClose = onClose
        self.onDrop = onDrop

        let s = Config.closeButtonSize
        self.closeBtnRect = NSRect(
            x: Config.padding + 4,
            y: frame.height - Config.padding - s - 4,
            width: s, height: s)

        super.init(frame: frame)

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: Config.padding, dy: Config.padding)
        let path = NSBezierPath(roundedRect: rect,
                                xRadius: Config.cornerRadius,
                                yRadius: Config.cornerRadius)

        // Shadow
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.4)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Image
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        image.draw(in: rect)
        NSColor(white: 0, alpha: 0.12).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Close button (hover only)
        if hovering {
            drawCloseButton()
        }

        // Badge count
        if badgeCount > 1 {
            drawBadge(count: badgeCount)
        }
    }

    private func drawCloseButton() {
        let circle = NSBezierPath(ovalIn: closeBtnRect)
        NSColor(white: 0, alpha: 0.6).setFill()
        circle.fill()

        let inset: CGFloat = 6
        let r = closeBtnRect.insetBy(dx: inset, dy: inset)
        let xPath = NSBezierPath()
        xPath.move(to: NSPoint(x: r.minX, y: r.minY))
        xPath.line(to: NSPoint(x: r.maxX, y: r.maxY))
        xPath.move(to: NSPoint(x: r.maxX, y: r.minY))
        xPath.line(to: NSPoint(x: r.minX, y: r.maxY))
        NSColor.white.setStroke()
        xPath.lineWidth = 1.5
        xPath.lineCapStyle = .round
        xPath.stroke()
    }

    private func drawBadge(count: Int) {
        let text = "\(count)"
        let font = NSFont.systemFont(ofSize: 12, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let badgeW = max(size.width + 12, 24)
        let badgeH: CGFloat = 24
        let badgeRect = NSRect(
            x: bounds.maxX - Config.padding - badgeW - 4,
            y: bounds.maxY - Config.padding - badgeH - 4,
            width: badgeW, height: badgeH)

        let path = NSBezierPath(roundedRect: badgeRect,
                                xRadius: badgeH / 2, yRadius: badgeH / 2)
        NSColor.systemRed.setFill()
        path.fill()

        let textRect = NSRect(
            x: badgeRect.midX - size.width / 2,
            y: badgeRect.midY - size.height / 2,
            width: size.width, height: size.height)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    // MARK: Mouse Events

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if closeBtnRect.contains(pt) {
            onClose()
        }
        dragOrigin = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let pt = convert(event.locationInWindow, from: nil)
        if hypot(pt.x - origin.x, pt.y - origin.y) > 5 {
            dragOrigin = nil
            startFileDrag(event)
        }
    }

    private func startFileDrag(_ event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let rect = bounds.insetBy(dx: Config.padding, dy: Config.padding)
        item.setDraggingFrame(rect, contents: image)
        _ = beginDraggingSession(with: [item], event: event, source: self)
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        if operation != [] {
            onDrop()
        }
    }
}
