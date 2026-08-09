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
        // 注意：不要设 isOpaque = false / backgroundColor = .clear。
        // behindWindow 材质由 NSVisualEffectView 自己采样窗口后方内容，无需窗口透明；
        // 一旦窗口非不透明，AppKit 不再绘制窗口背景，未被视图覆盖的边缘与圆角会露出黑色。
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 700, height: 470))
        window.center()
        self.init(window: window)
    }
}
