// DisplayToggle — menu bar / CLI tool to soft-disconnect external displays and change resolution.
// Uses the private CoreGraphics API CGSConfigureDisplayEnabled (same approach as BetterDisplay).
import AppKit
import CoreAudio
import CoreGraphics
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
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
        "resolution": "分辨率", "refresh": "刷新率", "default": "默认", "modes": "分辨率与刷新率",
        "brightness": "亮度", "volume": "音量", "unsupported": "不支持",
        "resetConnections": "重置连接", "forgotten": "未检测到，已移除",
        "resetTip": "重新检测这台显示器：线还插着就重新连接；已经拔掉就先从列表中移除，以后再插上时会自动重新出现。",
        "resetAllTip": "对所有显示器执行重置：重新连接所有被断开的显示器，并移除已经拔掉线的显示器记录。不会改动分辨率等其他设置。",
        "quit": "退出", "launchAtLogin": "登录时启动", "needsApproval": "需要在系统设置中允许", "approvalTitle": "DisplayToggle 需要你的授权", "approvalBody": "请在「系统设置 → 通用 → 登录项」中允许 DisplayToggle，才能登录时自动启动。", "openSettings": "打开系统设置", "later": "稍后", "language": "语言", "system": "跟随系统",
        "lastDisplay": "不能断开最后一个显示器",
        "failed": "操作失败",
        "keepAwake": "保持唤醒", "awakeActive": "生效中", "awakeIdle": "未生效", "awakeOff": "已关闭",
        "awakeAlways": "全部：始终保持唤醒", "awakeBattery": "仅电池：只在使用电池时保持唤醒", "awakeAC": "仅插电：只在接通电源时保持唤醒",
        "awakeTip": "让 Mac 持续运行、不进入睡眠，合上盖子、不接显示器时也一样（屏幕仍可正常关闭）。再次点击已选中的图标即可关闭。合盖时请勿将 Mac 放进包里，以免过热。",
        "awakeNoLid": "电池下合盖未授权",
        "awakeHelperPrompt": "DisplayToggle 需要管理员授权一次，才能在使用电池且合上盖子时阻止睡眠。",
    ]
    let en: [String: String] = [
        "connected": "Connected", "disconnected": "Disconnected", "main": "Main",
        "connect": "Connect", "disconnect": "Disconnect",
        "resolution": "Resolution", "refresh": "Refresh Rate", "default": "Default", "modes": "Resolution & Refresh Rate",
        "brightness": "Brightness", "volume": "Volume", "unsupported": "Not supported",
        "resetConnections": "Reset Connections", "forgotten": "not detected, removed",
        "resetTip": "Re-check this display: reconnect it if it's still plugged in; if it's been unplugged, remove it from the list until it's plugged back in.",
        "resetAllTip": "Reset every display: reconnect every disconnected display and drop displays that are physically unplugged. Resolution and other settings are left unchanged.",
        "quit": "Quit", "launchAtLogin": "Launch at Login", "needsApproval": "Needs approval in System Settings", "approvalTitle": "DisplayToggle needs your approval", "approvalBody": "Allow DisplayToggle in System Settings → General → Login Items to launch it at login.", "openSettings": "Open System Settings", "later": "Later", "language": "Language", "system": "System Default",
        "lastDisplay": "Can't disconnect the last display",
        "failed": "Operation failed",
        "keepAwake": "Keep Awake", "awakeActive": "Active", "awakeIdle": "Inactive", "awakeOff": "Off",
        "awakeAlways": "Always: stay awake all the time", "awakeBattery": "On Battery: stay awake only on battery power", "awakeAC": "Plugged In: stay awake only on AC power",
        "awakeTip": "Keep the Mac running instead of sleeping — even with the lid closed and no display attached (screens can still turn off). Click the selected icon again to turn it off. Don't put a closed, awake Mac in a bag — it can overheat.",
        "awakeNoLid": "lid on battery not authorized",
        "awakeHelperPrompt": "DisplayToggle needs administrator approval once to prevent sleep when the lid is closed on battery power.",
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

// MARK: - Brightness & volume

/// Look up a C function at runtime, so missing private symbols (e.g. on Intel) don't break linking.
func sym<T>(_ lib: String, _ name: String, _ type: T.Type) -> T? {
    guard let h = dlopen(lib, RTLD_LAZY), let p = dlsym(h, name) else { return nil }
    return unsafeBitCast(p, to: type)
}

/// DDC/CI to external displays over the private IOAVService API (Apple silicon only).
enum DDC {
    static let brightness: UInt8 = 0x10, volume: UInt8 = 0x62
    static let queue = DispatchQueue(label: "DisplayToggle.ddc")

    private static let iokit = "/System/Library/Frameworks/IOKit.framework/IOKit"
    private static let create = sym(iokit, "IOAVServiceCreateWithService",
        (@convention(c) (CFAllocator?, io_service_t) -> UnsafeMutableRawPointer?).self)
    private static let copyEDID = sym(iokit, "IOAVServiceCopyEDID",
        (@convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> IOReturn).self)
    private static let readI2C = sym(iokit, "IOAVServiceReadI2C",
        (@convention(c) (UnsafeMutableRawPointer, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn).self)
    private static let writeI2C = sym(iokit, "IOAVServiceWriteI2C",
        (@convention(c) (UnsafeMutableRawPointer, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn).self)

    /// Services of the active external displays, matched by EDID vendor/product/serial. Main thread only.
    static var services: [CGDirectDisplayID: AnyObject] = [:]
    /// Last known (value, max) per display and VCP code, so sliders open at the right spot. Main thread only.
    static var cache: [String: (cur: Int, max: Int)] = [:]
    static func key(_ id: CGDirectDisplayID, _ vcp: UInt8) -> String { "\(id)-\(vcp)" }

    static func refresh() {
        services = [:]
        guard let create, let copyEDID else { return }
        var it = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(it) }
        var found: [(vendor: UInt32, model: UInt32, serial: UInt32, svc: AnyObject)] = []
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            let loc = IORegistryEntryCreateCFProperty(s, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            guard loc as? String == "External", let p = create(kCFAllocatorDefault, s) else { continue }
            let svc = Unmanaged<AnyObject>.fromOpaque(p).takeRetainedValue()
            var out: UnsafeMutableRawPointer?
            guard copyEDID(p, &out) == kIOReturnSuccess, let out else { continue }
            let e = [UInt8](Unmanaged<CFData>.fromOpaque(out).takeRetainedValue() as Data)
            guard e.count >= 16 else { continue }
            found.append((UInt32(e[8]) << 8 | UInt32(e[9]), UInt32(e[10]) | UInt32(e[11]) << 8,
                          UInt32(e[12]) | UInt32(e[13]) << 8 | UInt32(e[14]) << 16 | UInt32(e[15]) << 24, svc))
        }
        for id in Displays.active() where CGDisplayIsBuiltin(id) == 0 {
            if let i = found.firstIndex(where: {
                $0.vendor == CGDisplayVendorNumber(id) && $0.model == CGDisplayModelNumber(id) && $0.serial == CGDisplaySerialNumber(id)
            }) { services[id] = found.remove(at: i).svc }
        }
    }

    private static func checksum(_ b: [UInt8]) -> UInt8 { b.reduce(0x6E ^ 0x51, ^) }

    /// Blocking (~50 ms per attempt) — call off the main thread in the app.
    static func read(_ svc: AnyObject, _ vcp: UInt8) -> (cur: Int, max: Int)? {
        guard let readI2C, let writeI2C else { return nil }
        let p = Unmanaged.passUnretained(svc).toOpaque()
        var req: [UInt8] = [0x82, 0x01, vcp]; req.append(checksum(req))
        for _ in 0..<3 {
            if writeI2C(p, 0x37, 0x51, &req, UInt32(req.count)) == kIOReturnSuccess {
                usleep(40_000)
                var rep = [UInt8](repeating: 0, count: 11)
                if readI2C(p, 0x37, 0x51, &rep, UInt32(rep.count)) == kIOReturnSuccess,
                   rep[2] == 0x02, rep[3] == 0, rep[4] == vcp {
                    let max = Int(rep[6]) << 8 | Int(rep[7])
                    if max > 0 { return (Int(rep[8]) << 8 | Int(rep[9]), max) }
                }
            }
            usleep(50_000)
        }
        return nil
    }

    static func write(_ svc: AnyObject, _ vcp: UInt8, _ value: Int) {
        guard let writeI2C else { return }
        let p = Unmanaged.passUnretained(svc).toOpaque()
        var req: [UInt8] = [0x84, 0x03, vcp, UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]; req.append(checksum(req))
        for _ in 0..<2 {
            if writeI2C(p, 0x37, 0x51, &req, UInt32(req.count)) == kIOReturnSuccess { return }
            usleep(20_000)
        }
    }

    private static var pending: [String: Int] = [:]
    private static let lock = NSLock()

    /// Queue a write from the main thread; while one is in flight only the latest value is kept,
    /// so dragging a slider doesn't pile up slow bus writes.
    static func set(_ svc: AnyObject, _ id: CGDirectDisplayID, _ vcp: UInt8, _ value: Int) {
        let k = key(id, vcp)
        if let c = cache[k] { cache[k] = (value, c.max) }
        lock.lock(); let idle = pending.updateValue(value, forKey: k) == nil; lock.unlock()
        guard idle else { return }
        queue.async {
            lock.lock(); let v = pending.removeValue(forKey: k); lock.unlock()
            if let v { write(svc, vcp, v); usleep(50_000) }  // give the monitor time before the next write
        }
    }
}

/// Built-in display brightness via the private DisplayServices framework.
enum BuiltIn {
    private static let lib = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    private static let get = sym(lib, "DisplayServicesGetBrightness",
        (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
    private static let set = sym(lib, "DisplayServicesSetBrightness",
        (@convention(c) (CGDirectDisplayID, Float) -> Int32).self)

    static func brightness(_ id: CGDirectDisplayID) -> Float? {
        var v: Float = 0
        guard let get, get(id, &v) == 0 else { return nil }
        return v
    }
    static func setBrightness(_ id: CGDirectDisplayID, _ v: Float) { _ = set?(id, v) }
}

/// Brightness 0–100 for any display; blocking, for the CLI.
enum Brightness {
    static func get(_ id: CGDirectDisplayID) -> Int? {
        if CGDisplayIsBuiltin(id) != 0 { return BuiltIn.brightness(id).map { Int(($0 * 100).rounded()) } }
        DDC.refresh()
        guard let svc = DDC.services[id], let r = DDC.read(svc, DDC.brightness) else { return nil }
        return min(100, r.cur * 100 / r.max)
    }
    static func set(_ id: CGDirectDisplayID, _ v: Int) -> Bool {
        if CGDisplayIsBuiltin(id) != 0 { BuiltIn.setBrightness(id, Float(v) / 100); return BuiltIn.brightness(id) != nil }
        DDC.refresh()
        guard let svc = DDC.services[id], let r = DDC.read(svc, DDC.brightness) else { return false }
        DDC.write(svc, DDC.brightness, v * r.max / 100)
        return true
    }
}

/// Volume of the default output device. Monitors over HDMI/DisplayPort usually have no
/// software volume, so callers fall back to DDC on the display with the same name.
enum Audio {
    private static func address(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    private static let mainVolume: AudioObjectPropertySelector = 0x766D7663  // 'vmvc', kAudioHardwareServiceDeviceProperty_VirtualMainVolume

    static func defaultOutput() -> AudioObjectID? {
        var dev = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev)
        return err == noErr && dev != 0 ? dev : nil
    }

    static func name(_ dev: AudioObjectID) -> String? {
        var name: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var a = address(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    /// 0–1, or nil if the device has no settable software volume.
    static func volume(_ dev: AudioObjectID) -> Float? {
        var a = address(mainVolume, kAudioDevicePropertyScopeOutput)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(dev, &a), AudioObjectIsPropertySettable(dev, &a, &settable) == noErr, settable.boolValue
        else { return nil }
        var v: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func setVolume(_ dev: AudioObjectID, _ v: Float) {
        var a = address(mainVolume, kAudioDevicePropertyScopeOutput)
        var value = Float32(v)
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    /// The display whose speakers are the default output, if its volume has to go over DDC.
    static func ddcDisplay(for dev: AudioObjectID) -> CGDirectDisplayID? {
        guard volume(dev) == nil, let n = name(dev) else { return nil }
        return Displays.active().first { Displays.name(of: $0) == n }
    }
}

/// Reconnect every disabled display. Returns whether any display was reconnected.
@discardableResult
func reconnectAll() -> Bool {
    let disabled = Displays.known().filter { !Displays.isEnabled($0.id) }
    for d in disabled { Displays.set(d.id, enabled: true) }
    return !disabled.isEmpty
}

/// Forget displays that are physically gone.
func forgetUnplugged() { Displays.save(Displays.known().filter { Displays.isEnabled($0.id) }) }

/// Forget one display if it's still not active, i.e. physically gone. Returns whether it was forgotten.
/// Plugging it back in makes it active again, and known() picks it up from there.
@discardableResult
func forgetIfGone(_ id: CGDirectDisplayID) -> Bool {
    if Displays.isEnabled(id) { return false }
    Displays.save(Displays.known().filter { $0.id != id })
    return true
}

/// Blocking version for the CLI; the menu bar app must not sleep on the main thread.
func resetAllConnections() {
    if reconnectAll() { Thread.sleep(forTimeInterval: 1.5) }  // let reconnected displays come online
    forgetUnplugged()
}

// MARK: - Keep awake

enum AwakeMode: String { case off, always, battery, ac }

/// Caffeinate-style keep-awake. Two IOPM assertions, like `caffeinate -i -s`: one stops idle sleep,
/// the other (honored on AC power only) also keeps the Mac running with the lid closed. On battery
/// the lid still sleeps it unless system sleep is disabled (`pmset disablesleep 1`), which needs
/// root, so a one-time sudoers rule lets us run exactly that command without a password.
enum KeepAwake {
    static let key = "keepAwake", ownedKey = "sleepDisabledByUs"
    static let sudoers = "/etc/sudoers.d/displaytoggle"
    private static var assertions: [IOPMAssertionID] = []
    private static var helperOK: Bool?
    private static var installing = false

    static var mode: AwakeMode {
        get { AwakeMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key); update() }
    }

    static func onBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return type as String == kIOPMBatteryPowerKey
    }

    /// Whether any battery is at or below 10%. Below that we stop disabling sleep, so a closed Mac
    /// on battery gets to sleep (and save its state) instead of running until it dies.
    static func batteryLow() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return list.contains { ps in
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { return false }
            return cur * 100 / max <= 10
        }
    }

    /// Whether the current mode applies to the current power source.
    static var isActive: Bool {
        switch mode {
        case .off: return false
        case .always: return true
        case .battery: return onBattery()
        case .ac: return !onBattery()
        }
    }

    /// Apply the saved mode and follow power source changes (plugging in / unplugging).
    static func start() {
        if let src = IOPSNotificationCreateRunLoopSource({ _ in KeepAwake.update() }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        update()
    }

    static func update() {
        let on = isActive
        if on && assertions.isEmpty {
            for type in [kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionTypePreventSystemSleep] {
                var id: IOPMAssertionID = 0
                if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "DisplayToggle Keep Awake" as CFString, &id) == kIOReturnSuccess { assertions.append(id) }
            }
        } else if !on { releaseAssertions() }
        setSleepDisabled(on && onBattery() && !batteryLow())
    }

    /// Undo everything, e.g. on quit, so the Mac never stays sleepless behind our back.
    static func stop() {
        releaseAssertions()
        setSleepDisabled(false)
    }

    private static func releaseAssertions() { assertions.forEach { IOPMAssertionRelease($0) }; assertions = [] }

    /// Whether a mode can be active on battery, where only `pmset disablesleep` survives a closed lid.
    static func needsHelper(_ m: AwakeMode) -> Bool { m == .always || m == .battery }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    static var helperInstalled: Bool {
        if helperOK != true { helperOK = run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]) }
        return helperOK!
    }

    /// Ask for an admin password once to install the sudoers rule, then report whether it's in place.
    /// Runs in a separate osascript process: shown from our own (menu bar, never frontmost) process,
    /// the password dialog doesn't get keyboard focus.
    static func installHelper(_ done: @escaping (Bool) -> Void) {
        if helperInstalled { done(true); return }
        guard !installing else { return }  // a password dialog is already up
        installing = true
        let line = "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        let sh = "f=$(/usr/bin/mktemp) && printf '%s\\n' '\(line)' > \"$f\" && /usr/sbin/visudo -cf \"$f\" && "
            + "/usr/bin/install -m 0440 -o root -g wheel \"$f\" \(sudoers); rc=$?; rm -f \"$f\"; exit $rc"
        let quoted = sh.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(quoted)\" with prompt \"\(L("awakeHelperPrompt"))\" with administrator privileges"
        DispatchQueue.global().async {
            run("/usr/bin/osascript", ["-e", script])
            DispatchQueue.main.async { installing = false; helperOK = nil; done(helperInstalled) }
        }
    }

    /// Whether system sleep is currently disabled (`pmset -g` shows "SleepDisabled 1").
    private static func sleepDisabled() -> Bool {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["-g"]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return out.split(separator: "\n").contains { $0.split(whereSeparator: \.isWhitespace) == ["SleepDisabled", "1"] }
    }

    private static func setSleepDisabled(_ on: Bool) {
        let owned = UserDefaults.standard.bool(forKey: ownedKey)
        // Only ever undo what we did ourselves; leave a user's own `pmset disablesleep` alone.
        guard on != owned, helperInstalled else { return }
        if on && sleepDisabled() { return }  // already disabled by the user: don't claim it
        if run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]) {
            UserDefaults.standard.set(on, forKey: ownedKey)
        }
    }
}

// MARK: - Menu bar app

/// A display's header row: name and status on the left, icon buttons on the right.
final class DisplayHeaderView: NSView {
    struct Button { let symbol: String; let tip: String; let tint: NSColor; let action: () -> Void }
    private let buttons: [Button]

    init(title: String, sub: String, buttons: [Button]) {
        self.buttons = buttons
        let name = NSTextField(labelWithString: title)
        name.font = .menuFont(ofSize: 0)
        let detail = NSTextField(labelWithString: sub)
        detail.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        let textW = max(name.fittingSize.width, detail.fittingSize.width)
        let width = max(260, 14 + textW + 12 + CGFloat(buttons.count) * 26 + 10)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 38))
        autoresizingMask = .width
        name.frame = NSRect(x: 14, y: 19, width: textW, height: 16)
        detail.frame = NSRect(x: 14, y: 4, width: textW, height: 14)
        [name, detail].forEach(addSubview)
        var x = width - 10
        for (i, b) in buttons.enumerated().reversed() {
            x -= 26
            let btn = NSButton(image: NSImage(systemSymbolName: b.symbol, accessibilityDescription: b.tip) ?? NSImage(),
                               target: self, action: #selector(clicked(_:)))
            btn.isBordered = false; btn.imagePosition = .imageOnly
            btn.tag = i; btn.toolTip = b.tip; btn.contentTintColor = b.tint
            btn.frame = NSRect(x: x, y: 9, width: 24, height: 20); btn.autoresizingMask = .minXMargin
            addSubview(btn)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked(_ sender: NSButton) {
        enclosingMenuItem?.menu?.cancelTracking()
        buttons[sender.tag].action()
    }
}

final class ModeItem: NSMenuItem { var displayID: CGDirectDisplayID = 0; var target_mode: Mode? }

/// A menu row with an icon, a slider and a percentage.
final class SliderView: NSView {
    let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    let label = NSTextField(labelWithString: "")
    var onChange: ((Int) -> Void)?
    private(set) var touched = false

    init(symbol: String, tip: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        autoresizingMask = .width
        toolTip = tip
        let icon = NSImageView(frame: NSRect(x: 30, y: 5, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        icon.contentTintColor = .secondaryLabelColor
        slider.frame = NSRect(x: 52, y: 3, width: 260 - 52 - 52, height: 20)
        slider.autoresizingMask = .width
        slider.controlSize = .small
        slider.isContinuous = true
        slider.isEnabled = false
        slider.target = self; slider.action = #selector(changed)
        label.frame = NSRect(x: 260 - 48, y: 5, width: 36, height: 16)
        label.autoresizingMask = .minXMargin
        label.alignment = .right
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        [icon, slider, label].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ value: Int, max: Int) {
        slider.maxValue = Double(max); slider.integerValue = value; slider.isEnabled = true; updateLabel()
    }
    private func updateLabel() { label.stringValue = "\(Int((slider.doubleValue / slider.maxValue * 100).rounded()))%" }
    @objc private func changed() { touched = true; updateLabel(); onChange?(slider.integerValue) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    var item: NSStatusItem!
    var relayout: DispatchWorkItem?
    var signals: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        // A plain SIGTERM (e.g. `pkill` in `make install`/`uninstall`) would skip applicationWillTerminate
        // and leave sleep disabled; route it through a normal quit instead.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume(); signals.append(src)
        }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // A large monitor next to a smaller MacBook; older systems lack that symbol, so fall back.
        item.button?.image = NSImage(systemSymbolName: "desktopcomputer.and.macbook", accessibilityDescription: "DisplayToggle")
            ?? NSImage(systemSymbolName: "display.2", accessibilityDescription: "DisplayToggle")
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false; item.menu = menu

        // Safety net: if every screen goes dark (e.g. the built-in display is disconnected and then
        // the external cable is unplugged), automatically reconnect everything.
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            guard flags.contains(.removeFlag) || flags.contains(.disabledFlag) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if Displays.active().isEmpty { reconnectAll() }
            }
        }, nil)

        // After a display change the menu bar is rebuilt and status items can end up overlapping;
        // once things settle, hide and re-show ours so the system lays it out again.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.relayout?.cancel()
            let work = DispatchWorkItem {
                guard let item = self?.item else { return }
                item.isVisible = false
                DispatchQueue.main.async { item.isVisible = true }
            }
            self?.relayout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }

        KeepAwake.start()
    }

    func applicationWillTerminate(_ n: Notification) { KeepAwake.stop() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        DDC.refresh()
        for d in Displays.known() {
            let on = Displays.isEnabled(d.id)
            let main = on && CGDisplayIsMain(d.id) != 0 ? " (\(L("main")))" : ""

            let sub = on ? Modes.current(d.id).map { "\($0.sizeLabel) · \($0.hzLabel)" } ?? L("connected") : L("disconnected")
            let id = d.id
            var buttons = [DisplayHeaderView.Button(
                symbol: on ? "cable.connector" : "cable.connector.slash", tip: on ? L("disconnect") : L("connect"),
                tint: on ? .controlAccentColor : .secondaryLabelColor, action: { [weak self] in self?.toggle(id) })]
            if !on {
                buttons.append(.init(symbol: "arrow.clockwise", tip: L("resetTip"), tint: .secondaryLabelColor,
                                     action: { [weak self] in self?.reset(id) }))
            }
            let header = NSMenuItem()
            header.view = DisplayHeaderView(title: d.name + main, sub: sub, buttons: buttons)
            menu.addItem(header)

            if on {
                let modes = NSMenuItem(title: L("modes"), action: nil, keyEquivalent: "")
                modes.indentationLevel = 1; modes.submenu = modesMenu(d.id)
                menu.addItem(modes)
                if let row = brightnessRow(d.id) { menu.addItem(row) }
            }
            menu.addItem(.separator())
        }
        if let dev = Audio.defaultOutput(), let row = volumeRow(dev) {
            menu.addItem(sectionHeader("\(L("volume")) · \(Audio.name(dev) ?? "")"))
            menu.addItem(row)
            menu.addItem(.separator())
        }
        let resetAll = NSMenuItem(title: L("resetConnections"), action: #selector(resetConnections), keyEquivalent: "r")
        resetAll.target = self; resetAll.toolTip = L("resetAllTip")
        menu.addItem(resetAll)
        menu.addItem(.separator())
        menu.addItem(awakeRow())
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

    /// Same look as a display row: status on the left, one icon per mode on the right, the
    /// selected one in the accent color. Clicking the selected icon turns keep-awake off.
    func awakeRow() -> NSMenuItem {
        let cur = KeepAwake.mode
        var sub = L(cur == .off ? "awakeOff" : KeepAwake.isActive ? "awakeActive" : "awakeIdle")
        if KeepAwake.needsHelper(cur) && !KeepAwake.helperInstalled { sub += " · \(L("awakeNoLid"))" }
        // Later SF Symbols first, older fallbacks after.
        let modes: [(AwakeMode, [String], String)] = [(.always, ["infinity"], "awakeAlways"),
            (.battery, ["battery.75percent", "battery.75", "battery.100"], "awakeBattery"),
            (.ac, ["powerplug", "bolt"], "awakeAC")]
        let buttons = modes.map { m, symbols, tip in
            DisplayHeaderView.Button(
                symbol: symbols.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? symbols[0],
                tip: L(tip), tint: m == cur ? .controlAccentColor : .secondaryLabelColor,
                action: { [weak self] in self?.setAwake(m == KeepAwake.mode ? .off : m) })
        }
        let item = NSMenuItem()
        item.view = DisplayHeaderView(title: L("keepAwake"), sub: sub, buttons: buttons)
        item.view?.toolTip = L("awakeTip")
        return item
    }

    func modesMenu(_ id: CGDirectDisplayID) -> NSMenu {
        let sub = NSMenu()
        sub.addItem(sectionHeader(L("resolution")))
        let cur = Modes.current(id)
        for m in Modes.sizes(id) {
            var title = m.sizeLabel
            if m.isDefault { title += " — \(L("default"))" }
            sub.addItem(modeItem(title, id, m, checked: m.sizeKey == cur?.sizeKey))
        }
        let rates = Modes.rates(id)
        if rates.count > 1 {
            sub.addItem(.separator())
            sub.addItem(sectionHeader(L("refresh")))
            for m in rates { sub.addItem(modeItem(m.hzLabel, id, m, checked: m.hz == cur?.hz)) }
        }
        return sub
    }

    func sliderItem(_ view: SliderView) -> NSMenuItem { let i = NSMenuItem(); i.view = view; return i }

    func brightnessRow(_ id: CGDirectDisplayID) -> NSMenuItem? {
        let view = SliderView(symbol: "sun.max", tip: L("brightness"))
        if CGDisplayIsBuiltin(id) != 0 {
            guard let v = BuiltIn.brightness(id) else { return nil }
            view.show(Int((v * 100).rounded()), max: 100)
            view.onChange = { BuiltIn.setBrightness(id, Float($0) / 100) }
        } else {
            guard let svc = DDC.services[id] else { return nil }
            loadDDC(view, svc, id, DDC.brightness)
        }
        return sliderItem(view)
    }

    func volumeRow(_ dev: AudioObjectID) -> NSMenuItem? {
        let view = SliderView(symbol: "speaker.wave.2", tip: L("volume"))
        if let v = Audio.volume(dev) {
            view.show(Int((v * 100).rounded()), max: 100)
            view.onChange = { Audio.setVolume(dev, Float($0) / 100) }
        } else if let id = Audio.ddcDisplay(for: dev), let svc = DDC.services[id] {
            loadDDC(view, svc, id, DDC.volume)
        } else { return nil }
        return sliderItem(view)
    }

    /// Show the cached value right away, then read the real one off the main thread (DDC is slow).
    func loadDDC(_ view: SliderView, _ svc: AnyObject, _ id: CGDirectDisplayID, _ vcp: UInt8) {
        let k = DDC.key(id, vcp)
        if let c = DDC.cache[k] { view.show(c.cur, max: c.max) }
        view.onChange = { DDC.set(svc, id, vcp, $0) }
        DDC.queue.async {
            let r = DDC.read(svc, vcp)
            DispatchQueue.main.async {
                guard let r else {
                    if DDC.cache[k] == nil { view.label.stringValue = ""; view.toolTip = L("unsupported") }
                    return
                }
                DDC.cache[k] = r
                if !view.touched { view.show(r.cur, max: r.max) }
            }
        }
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

    // Display changes run on the next run loop pass, after the menu has fully closed, so the
    // status bar isn't being torn down and relaid out while our menu is still tracking.
    func toggle(_ id: CGDirectDisplayID) {
        DispatchQueue.main.async {
            if let err = Displays.set(id, enabled: !Displays.isEnabled(id)) { self.alertLater(err) }
        }
    }

    @objc func setMode(_ sender: ModeItem) {
        guard let m = sender.target_mode else { return }
        let id = sender.displayID
        DispatchQueue.main.async {
            if let err = Modes.apply(id, m) { self.alertLater(err) }
        }
    }

    @objc func resetConnections() {
        DispatchQueue.main.async {
            // Wait for reconnected displays to come online without blocking the main thread.
            let delay: Double = reconnectAll() ? 1.5 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { forgetUnplugged() }
        }
    }

    /// Make the logical state match the physical one: reconnect if still plugged in, otherwise forget.
    func reset(_ id: CGDirectDisplayID) {
        DispatchQueue.main.async {
            Displays.set(id, enabled: true)
            // Wait for it to come online without blocking the main thread.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { forgetIfGone(id) }
        }
    }

    func setAwake(_ mode: AwakeMode) {
        DispatchQueue.main.async {
            KeepAwake.mode = mode  // the assertions work right away; the helper only adds lid-closed on battery
            guard KeepAwake.needsHelper(mode) else { return }
            // If the dialog is cancelled the menu header says so; picking the mode again asks again.
            KeepAwake.installHelper { if $0 { KeepAwake.update() } }
        }
    }

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

    // A menu bar app is never frontmost, so activate first or the alert opens behind other windows.
    func alert(_ s: String) { let a = NSAlert(); a.messageText = s; NSApp.activate(ignoringOtherApps: true); a.runModal() }

    /// Show an error once the display change has settled, so the modal doesn't block the relayout.
    func alertLater(_ s: String) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.alert(s) } }
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
               DisplayToggle brightness <display> [0-100]
               DisplayToggle volume [0-100]         volume of the current output device
               DisplayToggle reset [<display>]      reconnect if plugged in, else forget (all if omitted)
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
    case "brightness":
        guard args.count >= 2 else { usage() }
        let d = display(args[1])
        var value: Int?
        if args.count >= 3 {
            guard let v = Int(args[2]), (0...100).contains(v) else { usage() }
            // Monitors often ignore DDC reads right after a write, so report the value we set.
            value = Brightness.set(d.id, v) ? v : nil
        } else { value = Brightness.get(d.id) }
        guard let v = value else { print("\(d.name): \(L("brightness")) \(L("unsupported"))"); exit(2) }
        print("\(d.name): \(L("brightness")) \(v)%")
    case "volume":
        guard let dev = Audio.defaultOutput() else { print(L("failed")); exit(2) }
        let name = Audio.name(dev) ?? "?"
        let target = args.count >= 2 ? Int(args[1]) : nil
        if args.count >= 2, target == nil || !(0...100).contains(target!) { usage() }
        if Audio.volume(dev) != nil {
            if let t = target { Audio.setVolume(dev, Float(t) / 100) }
            print("\(name): \(L("volume")) \(Int(((Audio.volume(dev) ?? 0) * 100).rounded()))%")
        } else {
            DDC.refresh()
            guard let id = Audio.ddcDisplay(for: dev), let svc = DDC.services[id], let r = DDC.read(svc, DDC.volume)
            else { print("\(name): \(L("volume")) \(L("unsupported"))"); exit(2) }
            var cur = r.cur
            if let t = target { cur = t * r.max / 100; DDC.write(svc, DDC.volume, cur) }
            print("\(name): \(L("volume")) \(min(100, cur * 100 / r.max))%")
        }
    case "reset", "all-on":
        if args.count >= 2 {
            let d = display(args[1])
            if !Displays.isEnabled(d.id) {
                Displays.set(d.id, enabled: true)
                Thread.sleep(forTimeInterval: 1.5)  // let it come online
            }
            print("\(d.name): \(forgetIfGone(d.id) ? L("forgotten") : L("connected"))")
        } else {
            resetAllConnections()
            print(L("resetConnections") + " ✓")
        }
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
