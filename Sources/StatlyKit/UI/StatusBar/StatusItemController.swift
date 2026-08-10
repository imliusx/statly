import AppKit

/// 一次状态栏渲染的产物。key 用于"变了才画"：与上次相同则完全跳过 AppKit 调用。
struct RenderOutput {
    enum Content {
        case text(String)
        case image(NSImage)
    }

    let key: String
    let content: Content
    let tooltip: String
}

/// 单个指标模块对应的 NSStatusItem。左键弹该模块详情，右键弹菜单。
final class StatusItemController: NSObject {
    /// 图标两侧的额外留白。系统 variableLength 默认给 16pt，且每个状态栏项的窗口
    /// 两侧还各有 8pt 固定装饰（公开 API 无法控制）。这里取 0，即 app 侧能做到的最紧，
    /// 此时相邻模块图标之间的空白为 16pt（全部来自系统装饰）。
    private static let horizontalPadding: CGFloat = 0

    private let item: NSStatusItem
    private var lastKey: String?
    private var lastTooltip: String?
    private var lastLength: CGFloat?

    var onLeftClick: ((NSStatusBarButton) -> Void)?
    var onRightClick: (() -> Void)?

    init(autosaveName: String, toolTip: String) {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        item.autosaveName = autosaveName
        if let button = item.button {
            button.toolTip = toolTip
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func update(_ output: RenderOutput) {
        if output.tooltip != lastTooltip {
            lastTooltip = output.tooltip
            item.button?.toolTip = output.tooltip
        }
        guard output.key != lastKey else { return }
        lastKey = output.key
        guard let button = item.button else { return }
        switch output.content {
        case .text(let text):
            if button.image != nil { button.image = nil }
            button.title = text
            setLength(NSStatusItem.variableLength)
        case .image(let image):
            if !button.title.isEmpty { button.title = "" }
            button.image = image
            setLength(image.size.width + Self.horizontalPadding)
        }
    }

    /// 宽度未变就不要碰 `length`：赋值会触发整条菜单栏重新布局，
    /// 而绝大多数更新只是图像内容变了、宽度没变（读数区按模板定宽）。
    private func setLength(_ length: CGFloat) {
        guard length != lastLength else { return }
        lastLength = length
        item.length = length
    }

    func showMenu(_ menu: NSMenu) {
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func clicked() {
        if NSApplication.shared.currentEvent?.type == .rightMouseUp {
            onRightClick?()
        } else if let button = item.button {
            onLeftClick?(button)
        }
    }
}
