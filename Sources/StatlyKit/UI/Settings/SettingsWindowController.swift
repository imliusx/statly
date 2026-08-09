import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init(settings: AppSettings) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Statly 设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }
}
