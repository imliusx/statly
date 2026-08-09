import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init(settings: AppSettings, store: MetricStore) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, store: store))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Statly 设置"
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 660, height: 430))
        window.center()
        self.init(window: window)
    }
}
