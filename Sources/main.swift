// DisplayToggle — menu bar / CLI tool to soft-disconnect external displays and change resolution.
// Uses the private CoreGraphics API CGSConfigureDisplayEnabled (same approach as BetterDisplay).
import AppKit
import CoreGraphics
import ServiceManagement
import UserNotifications

@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef?, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError

// MARK: - Localization

var isChinese: Bool {
    switch UserDefaults.standard.string(forKey: "language") {
    case "zh": return true
    case "en": return false
    default: return (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
    }
}

func L(_ key: String) -> String {
    let zh: [String: String] = [
        "connected": "已连接", "disconnected": "已断开", "main": "主",
        "connect": "连接", "disconnect": "断开",
        "resolution": "分辨率", "refresh": "刷新率", "default": "默认",
        "resetConnections": "重置连接",
        "resetTip": "重新连接所有被断开的显示器，并移除已经拔掉线、无法再连接的显示器记录。不会改动分辨率等其他设置。",
        "quit": "退出", "launchAtLogin": "登录时启动", "needsApproval": "需要在系统设置中允许", "approvalTitle": "DisplayToggle 需要你的授权", "approvalBody": "请在「系统设置 → 通用 → 登录项」中允许 DisplayToggle，才能登录时自动启动。", "openSettings": "打开系统设置", "later": "稍后", "language": "语言", "system": "跟随系统",
        "lastDisplay": "不能断开最后一个显示器",
        "failed": "操作失败",
    ]
    let en: [String: String] = [
        "connected": "Connected", "disconnected": "Disconnected", "main": "Main",
        "connect": "Connect", "disconnect": "Disconnect",
        "resolution": "Resolution", "refresh": "Refresh Rate", "default": "Default",
        "resetConnections": "Reset Connections",
        "resetTip": "Reconnect every disconnected display and drop displays that are physically unplugged. Resolution and other settings are left unchanged.",
        "quit": "Quit", "launchAtLogin": "Launch at Login", "needsApproval": "Needs approval in System Settings", "approvalTitle": "DisplayToggle needs your approval", "approvalBody": "Allow DisplayToggle in System Settings → General → Login Items to launch it at login.", "openSettings": "Open System Settings", "later": "Later", "language": "Language", "system": "System Default",
        "lastDisplay": "Can't disconnect the last display",
        "failed": "Operation failed",
    ]
    return (isChinese ? zh : en)[key] ?? key
}

// MARK: - Displays

struct KnownDisplay: Codable { var id: UInt32; var name: String }

enum Displays {
    static let key = "knownDisplays"

    static func active() -> [CGDirectDisplayID] {
        var n: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
        CGGetActiveDisplayList(n, &ids, &n)
        return Array(ids.prefix(Int(n)))
    }

    static func name(of id: CGDirectDisplayID) -> String? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }?.localizedName
    }

    /// Known displays, including disabled ones (which vanish from the system list, so we remember them).
    static func known() -> [KnownDisplay] {
        var list: [KnownDisplay] = []
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([KnownDisplay].self, from: data) { list = saved }
        for id in active() {
            let n = name(of: id) ?? "Display \(id)"
            if let i = list.firstIndex(where: { $0.id == id }) { list[i].name = n }
            else { list.append(KnownDisplay(id: id, name: n)) }
        }
        save(list)
        return list
    }

    static func save(_ list: [KnownDisplay]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func isEnabled(_ id: CGDirectDisplayID) -> Bool { active().contains(id) }

    @discardableResult
    static func set(_ id: CGDirectDisplayID, enabled: Bool) -> String? {
        if !enabled {
            let act = active()
            if act.contains(id) && act.count <= 1 { return L("lastDisplay") }
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return L("failed") }
        let err = CGSConfigureDisplayEnabled(config, id, enabled)
        guard err == .success else { CGCancelDisplayConfiguration(config); return "\(L("failed")) (\(err.rawValue))" }
        let done = CGCompleteDisplayConfiguration(config, .forSession)
        return done == .success ? nil : "\(L("failed")) (\(done.rawValue))"
    }

    /// Accepts a 1-based index, a display ID, or part of the name.
    static func resolve(_ s: String) -> KnownDisplay? {
        let list = known()
        if let n = Int(s), n >= 1, n <= list.count { return list[n - 1] }
        if let n = UInt32(s), let d = list.first(where: { $0.id == n }) { return d }
        return list.first { $0.name.localizedCaseInsensitiveContains(s) }
    }
}

// MARK: - Display modes

struct Mode {
    let mode: CGDisplayMode
    var w: Int { mode.width }
    var h: Int { mode.height }
    var hiDPI: Bool { mode.pixelWidth > mode.width }
    var hz: Int { Int(mode.refreshRate.rounded()) }
    var isDefault: Bool { mode.ioFlags & 0x4 != 0 }  // kDisplayModeDefaultFlag
    var sizeKey: String { "\(w)x\(h)\(hiDPI ? "h" : "")" }

    var sizeLabel: String {
        var s = "\(w) × \(h)"
        if hiDPI { s += " (HiDPI)" }
        return s
    }
    var hzLabel: String { hz > 0 ? "\(hz) Hz" : "—" }
}

enum Modes {
    static func all(_ id: CGDirectDisplayID) -> [Mode] {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let raw = (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode]) ?? []
        return raw.filter { $0.isUsableForDesktopGUI() }.map(Mode.init)
    }

    static func current(_ id: CGDirectDisplayID) -> Mode? { CGDisplayCopyDisplayMode(id).map(Mode.init) }

    /// One entry per (size, HiDPI), preferring the current refresh rate, else the highest.
    static func sizes(_ id: CGDirectDisplayID) -> [Mode] {
        let cur = current(id)
        var best: [String: Mode] = [:]
        for m in all(id) {
            if let b = best[m.sizeKey] {
                let bMatch = b.hz == cur?.hz, mMatch = m.hz == cur?.hz
                if (mMatch && !bMatch) || (mMatch == bMatch && m.hz > b.hz) { best[m.sizeKey] = m }
            } else { best[m.sizeKey] = m }
        }
        return best.values.sorted { ($0.w, $0.h, $0.hiDPI ? 1 : 0) > ($1.w, $1.h, $1.hiDPI ? 1 : 0) }
    }

    /// Refresh rates available at the current size.
    static func rates(_ id: CGDirectDisplayID) -> [Mode] {
        guard let cur = current(id) else { return [] }
        var seen = Set<Int>()
        return all(id).filter { $0.sizeKey == cur.sizeKey }
            .sorted { $0.hz > $1.hz }
            .filter { seen.insert($0.hz).inserted }
    }

    @discardableResult
    static func apply(_ id: CGDirectDisplayID, _ m: Mode) -> String? {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return L("failed") }
        CGConfigureDisplayWithDisplayMode(config, id, m.mode, nil)
        let done = CGCompleteDisplayConfiguration(config, .permanently)
        return done == .success ? nil : "\(L("failed")) (\(done.rawValue))"
    }
}

/// Reconnect every disabled display, then forget displays that are physically gone.
func resetAllConnections() {
    let disabled = Displays.known().filter { !Displays.isEnabled($0.id) }
    for d in disabled { Displays.set(d.id, enabled: true) }
    if !disabled.isEmpty { Thread.sleep(forTimeInterval: 1.5) }  // let reconnected displays come online
    Displays.save(Displays.known().filter { Displays.isEnabled($0.id) })
}

// MARK: - Menu bar app

final class ModeItem: NSMenuItem { var displayID: CGDirectDisplayID = 0; var target_mode: Mode? }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "DisplayToggle")
        let menu = NSMenu(); menu.delegate = self; item.menu = menu

        // Safety net: if every screen goes dark (e.g. the built-in display is disconnected and then
        // the external cable is unplugged), automatically reconnect everything.
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            guard flags.contains(.removeFlag) || flags.contains(.disabledFlag) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if Displays.active().isEmpty {
                    for d in Displays.known() { Displays.set(d.id, enabled: true) }
                }
            }
        }, nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for d in Displays.known() {
            let on = Displays.isEnabled(d.id)
            let main = on && CGDisplayIsMain(d.id) != 0 ? " (\(L("main")))" : ""

            let header = NSMenuItem(title: d.name + main, action: nil, keyEquivalent: "")
            header.state = on ? .on : .off
            if on, let cur = Modes.current(d.id) {
                header.attributedTitle = titled(d.name + main, sub: "\(cur.sizeLabel) · \(cur.hzLabel)")
            } else if !on {
                header.attributedTitle = titled(d.name, sub: L("disconnected"))
            }
            let sub = NSMenu()
            let toggle = NSMenuItem(title: on ? L("disconnect") : L("connect"), action: #selector(toggle(_:)), keyEquivalent: "")
            toggle.tag = Int(d.id); toggle.target = self
            sub.addItem(toggle)

            if on {
                sub.addItem(.separator())
                sub.addItem(sectionHeader(L("resolution")))
                let cur = Modes.current(d.id)
                for m in Modes.sizes(d.id) {
                    var title = m.sizeLabel
                    if m.isDefault { title += " — \(L("default"))" }
                    sub.addItem(modeItem(title, d.id, m, checked: m.sizeKey == cur?.sizeKey))
                }
                let rates = Modes.rates(d.id)
                if rates.count > 1 {
                    sub.addItem(.separator())
                    sub.addItem(sectionHeader(L("refresh")))
                    for m in rates { sub.addItem(modeItem(m.hzLabel, d.id, m, checked: m.hz == cur?.hz)) }
                }
            }
            header.submenu = sub
            menu.addItem(header)
        }
        menu.addItem(.separator())
        let reset = NSMenuItem(title: L("resetConnections"), action: #selector(resetConnections), keyEquivalent: "r")
        reset.target = self; reset.toolTip = L("resetTip")
        menu.addItem(reset)
        menu.addItem(.separator())
        // Always reflect the real system state, read fresh each time the menu opens.
        let login = NSMenuItem(title: L("launchAtLogin"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        switch SMAppService.mainApp.status {
        case .enabled: login.state = .on
        case .requiresApproval:
            login.state = .mixed
            login.attributedTitle = titled(L("launchAtLogin"), sub: L("needsApproval"))
        default: login.state = .off
        }
        menu.addItem(login)
        let lang = NSMenuItem(title: L("language"), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        let curLang = UserDefaults.standard.string(forKey: "language") ?? ""
        for (code, title) in [("", L("system")), ("en", "English"), ("zh", "中文")] {
            let i = NSMenuItem(title: title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            i.representedObject = code; i.target = self; i.state = code == curLang ? .on : .off
            langMenu.addItem(i)
        }
        lang.submenu = langMenu
        menu.addItem(lang)
        menu.addItem(NSMenuItem(title: L("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func titled(_ title: String, sub: String) -> NSAttributedString {
        let s = NSMutableAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        s.append(NSAttributedString(string: "\n" + sub, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor]))
        return s
    }

    func sectionHeader(_ t: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return .sectionHeader(title: t) }
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; return i
    }

    func modeItem(_ title: String, _ id: CGDirectDisplayID, _ m: Mode, checked: Bool) -> NSMenuItem {
        let i = ModeItem(title: title, action: #selector(setMode(_:)), keyEquivalent: "")
        i.displayID = id; i.target_mode = m; i.target = self; i.state = checked ? .on : .off
        return i
    }

    @objc func toggle(_ sender: NSMenuItem) {
        let id = CGDirectDisplayID(sender.tag)
        if let err = Displays.set(id, enabled: !Displays.isEnabled(id)) { alert(err) }
    }

    @objc func setMode(_ sender: ModeItem) {
        guard let m = sender.target_mode, let err = Modes.apply(sender.displayID, m) else { return }
        alert(err)
    }

    @objc func resetConnections() { resetAllConnections() }

    @objc func setLanguage(_ sender: NSMenuItem) {
        let code = sender.representedObject as? String ?? ""
        if code.isEmpty { UserDefaults.standard.removeObject(forKey: "language") }
        else { UserDefaults.standard.set(code, forKey: "language") }
    }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        switch svc.status {
        case .enabled:
            do { try svc.unregister() } catch { alert("\(L("failed")): \(error.localizedDescription)") }
        case .requiresApproval:
            // Registered but blocked by the user in System Settings — only they can allow it.
            requestApproval()
        default:
            do { try svc.register() } catch {
                if svc.status != .requiresApproval { alert("\(L("failed")): \(error.localizedDescription)"); return }
            }
            if svc.status == .requiresApproval { requestApproval() }
        }
    }

    /// Tell the user via a system notification (click opens Login Items); fall back to an alert
    /// if notifications aren't allowed for this app.
    func requestApproval() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                guard granted else { self.approvalAlert(); return }
                let content = UNMutableNotificationContent()
                content.title = L("approvalTitle")
                content.body = L("approvalBody")
                center.add(UNNotificationRequest(identifier: "login-approval", content: content, trigger: nil)) { err in
                    if err != nil { DispatchQueue.main.async { self.approvalAlert() } }
                }
            }
        }
    }

    func approvalAlert() {
        let a = NSAlert()
        a.messageText = L("approvalTitle"); a.informativeText = L("approvalBody")
        a.addButton(withTitle: L("openSettings")); a.addButton(withTitle: L("later"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
    }

    // Clicking the notification opens Login Items.
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        SMAppService.openSystemSettingsLoginItems(); done()
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    func alert(_ s: String) { let a = NSAlert(); a.messageText = s; a.runModal() }
}

// MARK: - Entry

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
} else {
    _ = NSApplication.shared  // makes NSScreen available
    func usage() -> Never {
        print("""
        Usage: DisplayToggle                        launch the menu bar app
               DisplayToggle list                   list displays
               DisplayToggle off|on|toggle <display>
               DisplayToggle modes <display>        list resolutions
               DisplayToggle res <display> <W>x<H> [hidpi] [<Hz>]
               DisplayToggle reset                  reset connections (reconnect all)
               DisplayToggle login [on|off]         launch at login
        <display> = index, display ID, or part of the name
        """); exit(1)
    }
    func display(_ s: String) -> KnownDisplay {
        guard let d = Displays.resolve(s) else { usage() }
        return d
    }

    switch args.first {
    case "list":
        for (i, d) in Displays.known().enumerated() {
            let on = Displays.isEnabled(d.id)
            let main = on && CGDisplayIsMain(d.id) != 0 ? " (\(L("main")))" : ""
            let mode = on ? Modes.current(d.id).map { "  \($0.sizeLabel) @ \($0.hzLabel)" } ?? "" : ""
            print("\(i + 1). [\(L(on ? "connected" : "disconnected"))] \(d.name)\(main)  id=\(d.id)\(mode)")
        }
    case "on", "off", "toggle":
        guard args.count >= 2 else { usage() }
        let d = display(args[1])
        let target = args[0] == "on" ? true : args[0] == "off" ? false : !Displays.isEnabled(d.id)
        if let err = Displays.set(d.id, enabled: target) { print(err); exit(2) }
        print("\(d.name): \(L(target ? "connected" : "disconnected"))")
    case "modes":
        guard args.count >= 2 else { usage() }
        let d = display(args[1]); let cur = Modes.current(d.id)
        var seen = Set<String>()
        for m in Modes.all(d.id).sorted(by: { ($0.w, $0.h, $0.hz) > ($1.w, $1.h, $1.hz) })
        where seen.insert("\(m.sizeKey)@\(m.hz)").inserted {
            let mark = (m.sizeKey == cur?.sizeKey && m.hz == cur?.hz) ? "*" : " "
            print("\(mark) \(m.sizeLabel) @ \(m.hzLabel)\(m.isDefault ? "  [\(L("default"))]" : "")")
        }
    case "res":
        guard args.count >= 3 else { usage() }
        let d = display(args[1])
        let wh = args[2].lowercased().split(separator: "x").compactMap { Int($0) }
        guard wh.count == 2 else { usage() }
        let rest = args.dropFirst(3).map { $0.lowercased() }
        let wantHiDPI = rest.contains("hidpi")
        let wantHz = rest.compactMap { Int($0.replacingOccurrences(of: "hz", with: "")) }.first
        let candidates = Modes.all(d.id).filter { $0.w == wh[0] && $0.h == wh[1] && $0.hiDPI == wantHiDPI }
            .filter { wantHz == nil || $0.hz == wantHz }
            .sorted { $0.hz > $1.hz }
        guard let m = candidates.first else { print("No matching mode. Try: DisplayToggle modes \(args[1])"); exit(2) }
        if let err = Modes.apply(d.id, m) { print(err); exit(2) }
        print("\(d.name): \(m.sizeLabel) @ \(m.hzLabel)")
    case "reset", "all-on":
        resetAllConnections()
        print(L("resetConnections") + " ✓")
    case "login":
        let svc = SMAppService.mainApp
        do {
            if args.count >= 2 { try args[1] == "on" ? svc.register() : svc.unregister() }
        } catch { print("\(L("failed")): \(error.localizedDescription)"); exit(2) }
        let state: String
        switch svc.status {
        case .enabled: state = "on"
        case .requiresApproval: state = "off (\(L("needsApproval")))"
        default: state = "off"
        }
        print("\(L("launchAtLogin")): \(state)")
    default: usage()
    }
}
