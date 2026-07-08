import AppKit
import SwiftUI
import MenuBarCore

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    var onSave: ((AppConfig) throws -> Void)?
    var onSetLaunchAtLogin: ((Bool) -> Void)?

    func show(config: AppConfig, launchAtLogin: Bool) {
        let view = SettingsView(
            config: config,
            launchAtLogin: launchAtLogin,
            onSave: { [weak self] newConfig in
                guard let self else { return }

                do {
                    try self.onSave?(newConfig)
                    self.window?.close()
                } catch {
                    self.presentSaveError(error)
                }
            },
            setLaunchAtLogin: { [weak self] enabled in
                self?.onSetLaunchAtLogin?(enabled)
            })
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

    private func presentSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Nie udało się zapisać ustawień"
        alert.informativeText = Self.message(for: error)
        alert.addButton(withTitle: "OK")

        if let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private static func message(for error: Error) -> String {
        if let keychainError = error as? KeychainError {
            return keychainError.description
        }

        return error.localizedDescription
    }
}
