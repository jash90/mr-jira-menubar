import AppKit
import SwiftUI
import MenuBarCore

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    var onSave: ((AppConfig) -> Void)?

    func show(config: AppConfig) {
        let view = SettingsView(config: config) { [weak self] newConfig in
            self?.onSave?(newConfig)
            self?.window?.close()
        }
        let hosting = NSHostingController(rootView: view)

        let win = window ?? NSWindow(contentViewController: hosting)
        if window == nil {
            win.styleMask = [.titled, .closable]
            win.title = "MR Jira Menu Bar — Ustawienia"
            win.isReleasedWhenClosed = false
            window = win
        } else {
            win.contentViewController = hosting
        }

        NSApp.activate(ignoringOtherApps: true)
        win.center()
        win.makeKeyAndOrderFront(nil)
    }
}
