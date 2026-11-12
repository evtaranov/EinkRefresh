import AppKit
import Carbon.HIToolbox
import ServiceManagement

let defaults = UserDefaults.standard
var holdSeconds: Double = defaults.object(forKey: "holdSeconds") == nil ? 0.15 : defaults.double(forKey: "holdSeconds")
let einkDisplayName = defaults.string(forKey: "displayName") ?? "DS-DP"

struct HotKey {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    static let fallback = HotKey(keyCode: UInt32(kVK_F13), modifiers: 0, label: "F13")

    static func load() -> HotKey {
        let d = UserDefaults.standard
        guard let label = d.string(forKey: "hotKeyLabel") else { return fallback }
        return HotKey(keyCode: UInt32(d.integer(forKey: "hotKeyCode")),
                      modifiers: UInt32(d.integer(forKey: "hotKeyModifiers")),
                      label: label)
    }

    func save() {
        let d = UserDefaults.standard
        d.set(Int(keyCode), forKey: "hotKeyCode")
        d.set(Int(modifiers), forKey: "hotKeyModifiers")
        d.set(label, forKey: "hotKeyLabel")
    }

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    init(event: NSEvent) {
        let flags = event.modifierFlags
        var carbon: UInt32 = 0
        var text = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); text += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); text += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); text += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); text += "⌘" }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon, label: text + HotKey.keyName(event))
    }

    static let namedKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
        kVK_ForwardDelete: "Fwd Delete", kVK_Home: "Home", kVK_End: "End",
        kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    ]

    static func keyName(_ event: NSEvent) -> String {
        if let name = namedKeys[Int(event.keyCode)] { return name }
        let chars = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return chars.isEmpty ? "Key \(event.keyCode)" : chars
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var refreshItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var durationItem: NSMenuItem!
    var hotKey = HotKey.load()
    var hotKeyRef: EventHotKeyRef?
    var flashing = false
    var recorder: NSPanel?
    var recorderMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.clockwise.circle", accessibilityDescription: "E-ink refresh")

        let menu = NSMenu()
        refreshItem = NSMenuItem(title: "", action: #selector(flash), keyEquivalent: "")
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem(title: "Change hotkey…", action: #selector(recordHotKey), keyEquivalent: ""))
        durationItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let durations = NSMenu()
        for step in 1...10 {
            let item = NSMenuItem(title: String(format: "%.1f s", Double(step) / 10), action: #selector(pickDuration(_:)), keyEquivalent: "")
            item.tag = step
            durations.addItem(item)
        }
        durationItem.submenu = durations
        menu.addItem(durationItem)
        updateDurationState()
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateLoginState()

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.flash() }
            return noErr
        }, 1, &spec, nil, nil)
        if !registerHotKey() {
            hotKey = .fallback
            _ = registerHotKey()
        }
    }

    func registerHotKey() -> Bool {
        unregisterHotKey()
        let id = EventHotKeyID(signature: OSType(0x45494E4B), id: 1)
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        refreshItem.title = "Refresh screen  (\(hotKey.label))"
        if status != noErr { NSLog("Hotkey registration failed: \(status)") }
        return status == noErr
    }

    func unregisterHotKey() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
    }

    @objc func recordHotKey() {
        if recorder != nil { return }
        unregisterHotKey()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 90),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "EinkRefresh hotkey"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let label = NSTextField(labelWithString: "Press the new shortcut.\nEsc cancels. Current: \(hotKey.label)")
        label.alignment = .center
        label.frame = NSRect(x: 10, y: 20, width: 320, height: 50)
        panel.contentView?.addSubview(label)
        panel.center()
        recorder = panel
        recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if Int(event.keyCode) != kVK_Escape {
                let previous = self.hotKey
                self.hotKey = HotKey(event: event)
                if self.registerHotKey() {
                    self.hotKey.save()
                } else {
                    self.hotKey = previous
                }
            }
            self.recorder?.close()
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor = recorderMonitor { NSEvent.removeMonitor(monitor) }
        recorderMonitor = nil
        recorder = nil
        if hotKeyRef == nil { _ = registerHotKey() }
    }

    @objc func flash() {
        if flashing || recorder != nil { return }
        flashing = true
        let eink = NSScreen.screens.filter { $0.localizedName == einkDisplayName }
        let screens = eink.isEmpty ? NSScreen.screens : eink
        let windows: [NSWindow] = screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.level = .screenSaver
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.backgroundColor = .black
            w.orderFrontRegardless()
            return w
        }
        let hold = holdSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            windows.forEach { $0.backgroundColor = .white }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold * 2) {
            windows.forEach { $0.close() }
            self.flashing = false
        }
    }

    @objc func pickDuration(_ sender: NSMenuItem) {
        holdSeconds = Double(sender.tag) / 10
        defaults.set(holdSeconds, forKey: "holdSeconds")
        updateDurationState()
    }

    func updateDurationState() {
        durationItem.title = String(format: "Duration  %g s", holdSeconds)
        durationItem.submenu?.items.forEach { $0.state = abs(Double($0.tag) / 10 - holdSeconds) < 0.001 ? .on : .off }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Login item change failed: \(error)")
        }
        updateLoginState()
    }

    func updateLoginState() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
