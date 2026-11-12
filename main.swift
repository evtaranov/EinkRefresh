import AppKit
import Carbon.HIToolbox
import ServiceManagement

let holdSeconds = 0.15
let einkDisplayName = "DS-DP"

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var loginItem: NSMenuItem!
    var flashing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.clockwise.circle", accessibilityDescription: "E-ink refresh")

        let menu = NSMenu()
        let refresh = NSMenuItem(title: "Refresh screen", action: #selector(flash), keyEquivalent: "")
        refresh.keyEquivalent = String(UnicodeScalar(NSF13FunctionKey)!)
        refresh.keyEquivalentModifierMask = []
        menu.addItem(refresh)
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateLoginState()
        registerHotKey()
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.flash() }
            return noErr
        }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x45494E4B), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_F13), 0, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("F13 hotkey registration failed: \(status)") }
    }

    @objc func flash() {
        if flashing { return }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) {
            windows.forEach { $0.backgroundColor = .white }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds * 2) {
            windows.forEach { $0.close() }
            self.flashing = false
        }
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
