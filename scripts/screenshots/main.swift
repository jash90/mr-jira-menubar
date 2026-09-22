// Screenshot harness for the GitHub Pages site.
//
// Compiled by scripts/screenshots.sh together with the app's own, unmodified UI sources
// (StatusItemController, SettingsView, SettingsWindowController). Instead of talking to
// GitLab / GitHub / Jira, it feeds the real controllers fictitious counts, so no network,
// Keychain or UserDefaults state is touched.
//
// Usage: harness <scene> <outDir> <light|dark>
//   scenes: menu, menu-update, menu-error, menu-compact, needs-config, settings
import AppKit
import MenuBarCore

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: harness <scene> <outDir> <light|dark>\n".data(using: .utf8)!)
    exit(2)
}
let scene = args[1]
let outDir = args[2]
let appearanceName = args[3]

// Fixed, fictitious sample data.
let sampleGitLab = SourceResult(value: GitLabCounts(open: 4, ready: 2))
let sampleGitHub = SourceResult(value: GitHubCounts(open: 3, approved: 1))
let sampleJira = SourceResult(value: JiraCounts(
    backlog: 7, inProgress: 2, testingAwaiting: 3, testingAccepted: 12, testingRejected: 1))
let sampleRefresh: Date = {
    var c = DateComponents()
    c.year = 2026; c.month = 9; c.day = 23; c.hour = 9; c.minute = 41; c.second = 0
    return Calendar.current.date(from: c)!
}()
let allSources = SourceVisibility(gitlab: true, github: true, jira: true)
let sampleConfig = AppConfig(
    gitlabHost: "gitlab.example.com", gitlabToken: "glpat-EXAMPLE-not-a-token",
    jiraHost: "jira.example.com", jiraToken: "EXAMPLE-not-a-token",
    githubHost: "api.github.com", githubToken: "ghp_EXAMPLE_not_a_token")

func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

func run(_ tool: String, _ arguments: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = arguments
    try? p.run()
    p.waitUntilExit()
}

func windowNumbersOfThisProcess() -> [(id: Int, bounds: CGRect, layer: Int)] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let pid = Int(getpid())
    return info.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? Int) == pid,
              let id = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        return (id, rect, w[kCGWindowLayer as String] as? Int ?? 0)
    }
}

/// The status item lives in its own small window at the top edge of the main screen.
func statusItemWindow() -> NSWindow? {
    NSApp.windows.first { String(describing: type(of: $0)).contains("StatusBar") }
}

/// Captures the menu-bar strip around our status item only (never the neighbouring items).
func captureStatusItem(to path: String) {
    guard let win = statusItemWindow(), let screen = NSScreen.screens.first else {
        log("status item window not found"); return
    }
    let f = win.frame
    let pad: CGFloat = 10
    let top = screen.frame.maxY - f.maxY
    let rect = "\(Int(f.minX - pad)),\(Int(top)),\(Int(f.width + 2 * pad)),\(Int(f.height))"
    log("status item frame \(f) -> -R \(rect)")
    run("/usr/sbin/screencapture", ["-x", "-R", rect, path])
}

func captureWindow(id: Int, to path: String) {
    run("/usr/sbin/screencapture", ["-x", "-l", String(id), path])
}

@MainActor
final class Harness {
    let controller = StatusItemController()
    let settings = SettingsWindowController()

    func start() {
        controller.gitlabHost = sampleConfig.gitlabHost
        controller.jiraHost = sampleConfig.jiraHost
        controller.githubWebHost = "github.com"

        switch scene {
        case "menu":
            controller.update(gitlab: sampleGitLab, github: sampleGitHub, jira: sampleJira,
                              lastRefresh: sampleRefresh, visibility: allSources,
                              enabledCounters: Set(StatusCounter.allCases), update: nil)
        case "menu-compact":
            controller.update(gitlab: sampleGitLab, github: sampleGitHub, jira: sampleJira,
                              lastRefresh: sampleRefresh, visibility: allSources,
                              enabledCounters: [.gitlabOpen, .gitlabReady, .jiraInProgress, .jiraTestingRejected],
                              update: nil)
        case "menu-update":
            let release = ReleaseInfo(version: "1.5.0", tag: "v1.5.0",
                                      dmgURL: URL(string: "https://example.com/MRJiraMenuBar-1.5.0.dmg"),
                                      htmlURL: URL(string: "https://example.com/releases/v1.5.0"))
            controller.update(gitlab: sampleGitLab, github: sampleGitHub, jira: sampleJira,
                              lastRefresh: sampleRefresh, visibility: allSources,
                              enabledCounters: Set(StatusCounter.allCases), update: release)
        case "menu-error":
            let failed = SourceResult<GitLabCounts>(error: GitLabError.status(401).description)
            controller.update(gitlab: failed, github: sampleGitHub, jira: sampleJira,
                              lastRefresh: sampleRefresh, visibility: allSources,
                              enabledCounters: Set(StatusCounter.allCases), update: nil)
        case "needs-config":
            controller.showNeedsConfig()
        case "settings":
            controller.showNeedsConfig()
            settings.show(config: sampleConfig, launchAtLogin: true)
        default:
            log("unknown scene \(scene)"); exit(2)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.capture() }
    }

    func capture() {
        let base = "\(outDir)/\(scene)"

        if scene == "settings" {
            guard let win = NSApp.windows.first(where: { $0.title.contains("Ustawienia") }) else {
                log("settings window not found"); exit(1)
            }
            captureWindow(id: win.windowNumber, to: "\(base)-\(appearanceName).png")
            exit(0)
        }

        captureStatusItem(to: "\(base)-bar.png")

        guard let button = statusItemWindow()?.contentView?.subviews.compactMap({ $0 as? NSStatusBarButton }).first
            ?? findButton(in: statusItemWindow()?.contentView) else {
            log("status bar button not found"); exit(1)
        }

        // Park the pointer on the status item so no menu row is hover-highlighted in the
        // capture; the original position is restored before exiting.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let mouse = NSEvent.mouseLocation
        let originalPointer = CGPoint(x: mouse.x, y: primaryTop - mouse.y)
        let parkPointer = {
            // A real mouse-moved event (not just a warp) so an open menu drops its hover highlight.
            if let f = statusItemWindow()?.frame {
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                        mouseCursorPosition: CGPoint(x: f.midX, y: primaryTop - f.midY), mouseButton: .left)?
                    .post(tap: .cghidEventTap)
            }
        }
        parkPointer()

        // Status-item menus follow the menu bar's (system) appearance rather than
        // NSApp.appearance, so pin the requested one on the menu itself.
        statusMenu()?.appearance = NSApp.appearance

        // performClick blocks in menu tracking; a .common-mode timer still fires meanwhile.
        var attempts = 0
        let timer = Timer(timeInterval: 0.6, repeats: true) { timer in
            attempts += 1
            let wins = windowNumbersOfThisProcess()
            for w in wins { log("window \(w.id) layer \(w.layer) \(w.bounds)") }
            // Tick 1 re-parks the pointer (in case it strayed onto the menu); capture from tick 2 on,
            // once the tracking loop has processed that move.
            MainActor.assumeIsolated { parkPointer() }
            if attempts >= 2, let menu = wins.filter({ $0.layer > 0 && $0.bounds.height > 40 }).max(by: { $0.bounds.height < $1.bounds.height }) {
                captureWindow(id: menu.id, to: "\(base)-menu-\(appearanceName).png")
                captureStatusItem(to: "\(base)-bar-open.png")
                // Geometry for scripts/screenshots/process.py (global, top-left origin, points).
                if let f = statusItemWindow()?.frame {
                    let top = (NSScreen.screens.first?.frame.maxY ?? 0) - f.maxY
                    let meta = """
                    {"item": {"x": \(f.minX), "y": \(top), "w": \(f.width), "h": \(f.height), "pad": 10},
                     "menu": {"x": \(menu.bounds.minX), "y": \(menu.bounds.minY), "w": \(menu.bounds.width), "h": \(menu.bounds.height)}}
                    """
                    try? meta.write(toFile: "\(base)-meta-\(appearanceName).json", atomically: true, encoding: .utf8)
                }
            } else if attempts < 10 {
                // performClick occasionally doesn't open the menu (e.g. while a previous run's
                // menu is still being dismissed); fall back to popping the same NSMenu up
                // under the button ourselves.
                if attempts == 3, let menu = MainActor.assumeIsolated({ self.statusMenu() }) {
                    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
                }
                return
            } else {
                log("menu window not found")
            }
            timer.invalidate()
            CGWarpMouseCursorPosition(originalPointer)
            exit(0)
        }
        RunLoop.main.add(timer, forMode: .common)
        NSApp.activate(ignoringOtherApps: true)
        button.performClick(nil)
    }

    /// `statusItem` is private in StatusItemController; read it reflectively instead of
    /// changing app code.
    func statusMenu() -> NSMenu? {
        let item = Mirror(reflecting: controller).children.first { $0.label == "statusItem" }?.value as? NSStatusItem
        return item?.menu
    }

    func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let b = view as? NSStatusBarButton { return b }
        for sub in view.subviews { if let b = findButton(in: sub) { return b } }
        return nil
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: appearanceName == "light" ? .aqua : .darkAqua)
let harness = MainActor.assumeIsolated { Harness() }
MainActor.assumeIsolated { harness.start() }
app.run()
