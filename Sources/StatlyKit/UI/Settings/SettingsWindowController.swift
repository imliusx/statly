import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init(settings: AppSettings, store: MetricStore) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, store: store))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Statly 设置"
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        // 内容铺满到标题栏，两侧面板的玻璃材质得以连成一片
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        // behindWindow 材质需要窗口本身透明才能透出后方内容
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 700, height: 470))
        window.center()
        self.init(window: window)
    }
}
