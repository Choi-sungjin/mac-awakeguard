import AppKit
import Foundation
import IOKit.pwr_mgt
import IOKit.ps

final class Shell {
    static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval = 5) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var output = Data()
        let lock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock()
            output.append(chunk)
            lock.unlock()
        }
        do { try process.run() } catch { return (-1, "\(error)") }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            pipe.fileHandleForReading.readabilityHandler = nil
            return (-2, "timeout")
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        let tail = pipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock()
        output.append(tail)
        let data = output
        lock.unlock()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

func commandLineLaunchdRunning(_ label: String) -> Bool {
    let result = Shell.run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"])
    return result.1.contains("state = running")
}

func commandLineClamshellClosed() -> Bool {
    let result = Shell.run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "4"])
    return result.1.contains("AppleClamshellState\" = Yes")
}

func commandLineHealthSummary() -> String {
    let gateway = commandLineLaunchdRunning("ai.hermes.gateway-hera") ? "Gateway OK" : "Gateway failed"
    let paperclip = commandLineLaunchdRunning("ai.paperclip.default") ? "Paperclip OK" : "Paperclip failed"
    let curl = Shell.run("/usr/bin/curl", ["-sS", "-m", "3", "http://127.0.0.1:3100/api/health"])
    let paperclipHttp = (curl.0 == 0 && curl.1.contains("ok")) ? "HTTP OK" : "HTTP failed"
    let lidWarning = commandLineClamshellClosed() ? " / warning: lid closed; macOS may enter Clamshell Sleep, so remote calls are not guaranteed" : ""
    return "\(gateway), \(paperclip), \(paperclipHttp)\(lidWarning)"
}

func runCommandLineModeIfRequested() {
    if CommandLine.arguments.contains("--health-check") {
        print(commandLineHealthSummary())
        exit(0)
    }

    guard let idx = CommandLine.arguments.firstIndex(of: "--assert-seconds"),
          CommandLine.arguments.indices.contains(idx + 1),
          let seconds = Int(CommandLine.arguments[idx + 1]),
          seconds > 0 else { return }

    var systemAssertion = IOPMAssertionID(0)
    var displayAssertion = IOPMAssertionID(0)
    let reason = "Hera Awake Guard - QA Smoke" as CFString
    let systemResult = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &systemAssertion)
    let displayResult = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &displayAssertion)
    print("systemAssertion=\(systemResult == kIOReturnSuccess ? "created" : "failed") displayAssertion=\(displayResult == kIOReturnSuccess ? "created" : "failed") seconds=\(seconds)")
    fflush(stdout)
    sleep(UInt32(seconds))
    if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion) }
    if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion) }
    print("released")
    exit(systemResult == kIOReturnSuccess ? 0 : 1)
}

enum AwakeMode: Equatable {
    case off
    case timed(hours: Int, end: Date)
    case infinite
    case gatewayGuard

    var label: String {
        switch self {
        case .off: return "꺼짐"
        case .timed(let hours, let end):
            let mins = max(0, Int(ceil(end.timeIntervalSinceNow / 60)))
            return "\(hours)시간 유지 · 남은 \(mins)분"
        case .infinite: return "무한 유지"
        case .gatewayGuard: return "Gateway Guard"
        }
    }

    var assertionReason: String {
        switch self {
        case .off: return "Off"
        case .timed(let hours, _): return "\(hours) Hour Timer"
        case .infinite: return "Infinite"
        case .gatewayGuard: return "Gateway Guard"
        }
    }

    var isActive: Bool {
        if case .off = self { return false }
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu = NSMenu()
    private var mode: AwakeMode = .off
    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var timer: Timer?
    private var statusImage: NSImage?
    private var lastHealth = "시작 중"
    private var lastTickAt: Date?
    private var lastLidClosed: Bool?
    private var lidClosedAt: Date?
    private let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HeraAwakeGuard.log").path
    private var usagePath: String { Bundle.main.path(forResource: "usage", ofType: "html") ?? "" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOlderInstances()
        ProcessInfo.processInfo.disableAutomaticTermination("Hera Awake Guard keeps a menu bar status item and power assertion alive")
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusButton(symbol: "⚪️")
        statusItem.menu = menu
        registerScreenSleepNotification()
        rebuildMenu()
        appendLog("launched")
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        if CommandLine.arguments.contains("--start-indefinite") {
            setMode(.infinite)
        } else if CommandLine.arguments.contains("--start-gateway-guard") {
            setMode(.gatewayGuard)
        } else if let hours = startupHours() {
            enableTimed(hours: hours)
        } else {
            setMode(.gatewayGuard)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showLaunchFeedback()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLaunchFeedback()
        return true
    }

    private func terminateOlderInstances() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "ai.aifa.HeraAwakeGuard"
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where app.processIdentifier != currentPID {
            appendLog("terminateOlderInstance pid=\(app.processIdentifier)")
            app.terminate()
        }
    }

    private func showLaunchFeedback() {
        let onAC = isOnACPower()
        let extDisplay = hasExternalDisplay()
        let body: String
        switch (onAC, extDisplay) {
        case (true, true):
            body = "Gateway Guard 켜짐. AC 전원 + 외부 디스플레이 감지됨 — Bluetooth/USB 키보드·마우스·트랙패드가 있으면 공식 Clamshell 조건에서 awake 유지 가능성이 높습니다."
        case (true, false):
            body = "Gateway Guard 켜짐. AC 전원은 연결됐지만 외부 디스플레이가 없어 커버를 닫으면 macOS Clamshell Sleep 정책에 따라 Telegram 호출이 끊길 수 있습니다."
        case (false, _):
            body = "Gateway Guard 켜짐. 배터리 모드입니다. 커버를 닫는 순간 macOS가 Clamshell Sleep으로 진입하므로 Telegram 호출 유지가 보장되지 않습니다. AC 전원 + 외부 디스플레이를 권장합니다."
        }
        appendLog("launchFeedback=notification ac=\(onAC) extDisplay=\(extDisplay)")
        let safeBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(safeBody)\" with title \"mac-awakeguard 실행 중\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        if let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? {
            return type == kIOPMACPowerKey
        }
        return false
    }

    private func hasExternalDisplay() -> Bool {
        return NSScreen.screens.count > 1
    }

    private func startupHours() -> Int? {
        guard let idx = CommandLine.arguments.firstIndex(of: "--start-hours"), CommandLine.arguments.indices.contains(idx + 1) else { return nil }
        return Int(CommandLine.arguments[idx + 1]).flatMap { (1...25).contains($0) ? $0 : nil }
    }

    private func registerScreenSleepNotification() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "🦉 Hera Awake Guard", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "상태: \(mode.label)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "점검: \(lastHealth)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let timeMenu = NSMenu()
        for hour in 1...25 {
            let title = hour == 1 ? "1시간" : "\(hour)시간"
            let item = NSMenuItem(title: title, action: #selector(enableTimedFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = hour
            timeMenu.addItem(item)
        }
        let timeRoot = NSMenuItem(title: "시간 선택", action: nil, keyEquivalent: "")
        timeRoot.submenu = timeMenu
        menu.addItem(timeRoot)

        menu.addItem(item("무한 유지", #selector(enableInfinite)))
        menu.addItem(item("Gateway Guard", #selector(enableGatewayGuard)))
        menu.addItem(item("끄기 · 원래 상태", #selector(turnOff)))
        menu.addItem(.separator())
        menu.addItem(item("잠금 화면으로 전환하고 끄기", #selector(lockScreenAndTurnOff)))
        menu.addItem(item("잠금 화면으로 전환 · Gateway Guard 유지", #selector(lockScreenKeepGatewayGuard)))
        menu.addItem(item("디스플레이만 끄기 · 커버 열어두기", #selector(displaySleepKeepGatewayGuard)))
        menu.addItem(.separator())
        menu.addItem(item("지금 상태 점검", #selector(runHealthNow)))
        menu.addItem(item("로그 열기", #selector(openLogs)))
        menu.addItem(item("사용법 열기", #selector(openUsage)))
        menu.addItem(.separator())
        menu.addItem(item("종료", #selector(quit)))
    }

    private func item(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func turnOff() { setMode(.off) }
    @objc private func enableTimedFromMenu(_ sender: NSMenuItem) {
        if let hours = sender.representedObject as? Int { enableTimed(hours: hours) }
    }
    private func enableTimed(hours: Int) { setMode(.timed(hours: hours, end: Date().addingTimeInterval(TimeInterval(hours * 3600)))) }
    @objc private func enableInfinite() { setMode(.infinite) }
    @objc private func enableGatewayGuard() { setMode(.gatewayGuard) }
    @objc private func runHealthNow() { tick(force: true) }
    @objc private func quit() { releaseAssertions(); appendLog("quit"); NSApp.terminate(nil) }

    @objc private func lockScreenAndTurnOff() {
        appendLog("lockScreenAndTurnOff=requested")
        setMode(.off)
        _ = Shell.run("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", ["-suspend"], timeout: 3)
    }

    @objc private func lockScreenKeepGatewayGuard() {
        appendLog("lockScreenKeepGatewayGuard=requested")
        setMode(.gatewayGuard)
        _ = Shell.run("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", ["-suspend"], timeout: 3)
    }

    @objc private func displaySleepKeepGatewayGuard() {
        appendLog("displaySleepKeepGatewayGuard=requested")
        setMode(.gatewayGuard)
        _ = Shell.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 3)
    }

    @objc private func screensDidSleep() {
        appendLog("screensDidSleep=keep current mode; display slept but awake assertion remains if active")
        tick(force: true)
    }

    @objc private func openLogs() {
        ensureLogExists()
        NSWorkspace.shared.open(URL(fileURLWithPath: logFile))
    }

    @objc private func openUsage() {
        if FileManager.default.fileExists(atPath: usagePath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: usagePath))
        }
    }

    private func setMode(_ newMode: AwakeMode) {
        mode = newMode
        if newMode.isActive { createAssertions(reason: newMode.assertionReason) } else { releaseAssertions() }
        appendLog("mode=\(newMode.label)")
        tick(force: true)
    }

    private func configureStatusButton(symbol: String) {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.imagePosition = .noImage
        button.title = "\(symbol)🦉"
        button.toolTip = "Hera Awake Guard · \(mode.label) · \(lastHealth)"
    }

    private func tick(force: Bool = false) {
        let now = Date()
        if let prev = lastTickAt {
            let gap = now.timeIntervalSince(prev)
            if gap >= 30 {
                appendLog(String(format: "wakeFromSleepDetected gap=%.1fs (timer paused — system was asleep)", gap))
            }
        }
        lastTickAt = now

        if case .timed(_, let end) = mode, now > end { setMode(.off); return }
        if mode.isActive { createAssertions(reason: mode.assertionReason) }
        let health = healthSummary()
        lastHealth = health
        let closed = clamshellClosed()
        if let prevClosed = lastLidClosed, prevClosed != closed {
            if closed {
                lidClosedAt = now
                appendLog("lidStateChanged closed=true ac=\(isOnACPower()) extDisplay=\(hasExternalDisplay()) note=bluetooth-input-helps-only-with-official-clamshell")
            } else {
                let duration = lidClosedAt.map { now.timeIntervalSince($0) } ?? 0
                appendLog(String(format: "lidStateChanged closed=false durationClosed=%.1fs", duration))
                lidClosedAt = nil
            }
        }
        lastLidClosed = closed
        let lid = closed ? "덮개닫힘" : "덮개열림"
        let symbol = mode.isActive ? (health.contains("주의") || health.contains("위험") || health.contains("실패") ? "⚠️" : "🟢") : "⚪️"
        configureStatusButton(symbol: symbol)
        if force || mode == .gatewayGuard { appendLog("health=\(health), lid=\(lid)") }
        rebuildMenu()
    }

    private func createAssertions(reason: String) {
        if systemAssertion == 0 {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Hera Awake Guard - \(reason)" as CFString, &id)
            if result == kIOReturnSuccess { systemAssertion = id; appendLog("systemAssertion=created id=\(id)") } else { appendLog("systemAssertion=failed result=\(result)") }
        }
        if displayAssertion == 0 {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Hera Awake Guard - \(reason)" as CFString, &id)
            if result == kIOReturnSuccess { displayAssertion = id; appendLog("displayAssertion=created id=\(id)") } else { appendLog("displayAssertion=failed result=\(result)") }
        }
    }

    private func releaseAssertions() {
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion); appendLog("systemAssertion=released id=\(systemAssertion)"); systemAssertion = 0 }
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion); appendLog("displayAssertion=released id=\(displayAssertion)"); displayAssertion = 0 }
    }

    private func healthSummary() -> String {
        let gateway = launchdRunning("ai.hermes.gateway-hera") ? "Gateway OK" : "Gateway 실패"
        let paperclip = launchdRunning("ai.paperclip.default") ? "Paperclip OK" : "Paperclip 실패"
        let curl = Shell.run("/usr/bin/curl", ["-sS", "-m", "3", "http://127.0.0.1:3100/api/health"])
        let paperclipHttp = (curl.0 == 0 && curl.1.contains("ok")) ? "HTTP OK" : "HTTP 실패"
        let lidWarning = clamshellClosed() ? " / 위험: 덮개 닫힘·Clamshell Sleep 시 호출 불가" : ""
        return "\(gateway), \(paperclip), \(paperclipHttp)\(lidWarning)"
    }

    private func launchdRunning(_ label: String) -> Bool {
        let result = Shell.run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"])
        return result.1.contains("state = running")
    }

    private func clamshellClosed() -> Bool {
        let result = Shell.run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "4"])
        return result.1.contains("AppleClamshellState\" = Yes")
    }

    private func ensureLogExists() {
        if !FileManager.default.fileExists(atPath: logFile) {
            FileManager.default.createFile(atPath: logFile, contents: nil)
        }
    }

    private func appendLog(_ line: String) {
        ensureLogExists()
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(stamp)] \(line)\n"
        if let data = text.data(using: .utf8), let handle = FileHandle(forWritingAtPath: logFile) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        }
    }
}

runCommandLineModeIfRequested()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
