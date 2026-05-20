import AppKit
import Foundation
import IOKit.pwr_mgt

final class Shell {
    static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval = 5) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return (-2, "timeout") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
    let lidWarning = commandLineClamshellClosed() ? " / warning: lid closed" : ""
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
    private let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HeraAwakeGuard.log").path
    private var usagePath: String { Bundle.main.path(forResource: "usage", ofType: "html") ?? "" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Hera Awake Guard keeps a menu bar status item and power assertion alive")
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusButton(symbol: "⚪️")
        statusItem.menu = menu
        registerSessionNotifications()
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

    private func showLaunchFeedback() {
        appendLog("launchFeedback=notification")
        let script = """
        display notification "Gateway Guard를 바로 켰습니다. 커버를 덮어도 Gateway가 유지되도록 시도합니다. 단, 배터리/가방/하드웨어 sleep은 macOS 안전 정책을 따릅니다." with title "mac-awakeguard 실행 중"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private func startupHours() -> Int? {
        guard let idx = CommandLine.arguments.firstIndex(of: "--start-hours"), CommandLine.arguments.indices.contains(idx + 1) else { return nil }
        return Int(CommandLine.arguments[idx + 1]).flatMap { (1...25).contains($0) ? $0 : nil }
    }

    private func registerSessionNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sessionWillLockOrResign), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
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

    @objc private func sessionWillLockOrResign() {
        appendLog("sessionDidResignActive=release assertions and return to off")
        setMode(.off)
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
        if case .timed(_, let end) = mode, Date() > end { setMode(.off); return }
        if mode.isActive { createAssertions(reason: mode.assertionReason) }
        let health = healthSummary()
        lastHealth = health
        let lid = clamshellClosed() ? "덮개닫힘" : "덮개열림"
        let symbol = mode.isActive ? (health.contains("주의") || health.contains("실패") ? "⚠️" : "🟢") : "⚪️"
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
        let lidWarning = clamshellClosed() ? " / 주의: 덮개 닫힘" : ""
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
