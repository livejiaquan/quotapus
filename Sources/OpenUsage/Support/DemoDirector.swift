import AppKit

/// Plays a timed script against the real dashboard for hands-free demo recordings: opens the panel,
/// clicks controls by sending mouse events to the panel itself (the system pointer never moves), and
/// picks Usage From entries. Only runs in demo mode with `QUOTAPUS_DEMO_SCRIPT=/path/to/script.json`.
/// Each step is logged with its screen position so a recording can draw the pointer afterwards.
struct DemoScript: Decodable {
    struct Step: Decodable {
        /// Seconds after the script starts.
        var at: Double
        /// `open`, `close`, `click` (x, y in panel points from its top-left), or `menu` (click x, y,
        /// then choose the item titled `item`).
        var action: String
        var x: Double?
        var y: Double?
        var item: String?
    }

    /// The panel opens below the top-right corner of the display whose name contains this.
    var screen: String
    /// Distance from the display's right edge to the panel's anchor, in points.
    var anchorInset: Double
    /// Where to write the menu-bar strip image and the step log.
    var statusImagePath: String?
    var logPath: String
    var steps: [Step]
}

@MainActor
final class DemoDirector: NSObject {
    static let environmentKey = "QUOTAPUS_DEMO_SCRIPT"

    private let script: DemoScript
    private let panel: NSPanel
    private let open: () -> Void
    private let close: () -> Void
    private let statusImage: () -> NSImage?
    private var log: [[String: Any]] = []
    private var trackingMenu: NSMenu?

    /// `nil` unless demo mode is on and a script is set; a set but unreadable script stops the launch.
    static func make(panel: NSPanel, open: @escaping () -> Void, close: @escaping () -> Void,
                     statusImage: @escaping () -> NSImage?) -> DemoDirector? {
        guard DemoMode.isActive,
              let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else { return nil }
        do {
            let script = try JSONDecoder().decode(DemoScript.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            return DemoDirector(script: script, panel: panel, open: open, close: close, statusImage: statusImage)
        } catch {
            AppLog.error(.config, "demo script \(path) couldn't be read: \(error)")
            fatalError("Demo script \(path) couldn't be read: \(error)")
        }
    }

    private init(script: DemoScript, panel: NSPanel, open: @escaping () -> Void, close: @escaping () -> Void,
                 statusImage: @escaping () -> NSImage?) {
        self.script = script
        self.panel = panel
        self.open = open
        self.close = close
        self.statusImage = statusImage
        super.init()
    }

    /// Where the panel hangs from: a status-item-sized rect under the menu bar of the chosen display.
    var anchorRect: NSRect? {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName.contains(script.screen) }) else {
            AppLog.error(.config, "demo script: no display named \(script.screen)")
            return nil
        }
        let top = screen.visibleFrame.maxY
        return NSRect(x: screen.frame.maxX - script.anchorInset, y: top, width: 28, height: screen.frame.maxY - top)
    }

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidBeginTracking(_:)),
                                               name: NSMenu.didBeginTrackingNotification, object: nil)
        let started = Date()
        Task { @MainActor in
            for step in script.steps {
                let wait = step.at - Date().timeIntervalSince(started)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                await perform(step)
            }
            writeLog()
        }
    }

    @objc private func menuDidBeginTracking(_ note: Notification) {
        trackingMenu = note.object as? NSMenu
    }

    private func perform(_ step: DemoScript.Step) async {
        var entry: [String: Any] = ["t": Date().timeIntervalSince1970, "action": step.action]
        switch step.action {
        case "open":
            if let path = script.statusImagePath, let image = statusImage(),
               let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            open()
        case "close":
            close()
        case "click", "menu":
            let point = windowPoint(step)
            entry.merge(screenPosition(point)) { $1 }
            postClick(at: point)
            if step.action == "menu", let item = step.item {
                try? await Task.sleep(for: .milliseconds(900))
                if let menu = trackingMenu, let index = menu.items.firstIndex(where: { $0.title == item }) {
                    entry["menuItems"] = menu.items.map(\.title)
                    menu.performActionForItem(at: index)
                    menu.cancelTracking()
                } else {
                    AppLog.error(.config, "demo script: no open menu with an item titled \(item)")
                }
                trackingMenu = nil
            }
        default:
            AppLog.error(.config, "demo script: unknown action \(step.action)")
        }
        entry["panel"] = ["x": panel.frame.minX, "y": panel.frame.maxY, "w": panel.frame.width,
                          "h": panel.frame.height, "window": panel.windowNumber]
        log.append(entry)
        writeLog()
    }

    /// Panel points from the top-left → window coordinates (bottom-left origin).
    private func windowPoint(_ step: DemoScript.Step) -> NSPoint {
        NSPoint(x: step.x ?? 0, y: panel.frame.height - (step.y ?? 0))
    }

    /// Global screen position, top-left origin (the convention screen recordings use).
    private func screenPosition(_ point: NSPoint) -> [String: Any] {
        let onScreen = panel.convertPoint(toScreen: point)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return ["screenX": onScreen.x, "screenY": primaryHeight - onScreen.y]
    }

    private func postClick(at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: panel.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private func writeLog() {
        guard let data = try? JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted]) else { return }
        try? data.write(to: URL(fileURLWithPath: script.logPath))
    }
}
