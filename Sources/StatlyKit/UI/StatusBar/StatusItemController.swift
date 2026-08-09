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

/// 一个状态栏 item（独立模式下对应单个模块，合并模式下承载全部模块）。
/// 左键弹详情，右键弹菜单。
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private var lastKey: String?
    private var lastTooltip: String?

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
            button.image = nil
            button.title = text
        case .image(let image):
            button.title = ""
            button.image = image
        }
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
