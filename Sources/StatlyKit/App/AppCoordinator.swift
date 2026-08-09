import AppKit
import Combine
import SwiftUI

/// 总协调器：持有设置/仓库/采样器/调度器，驱动状态栏渲染与弹窗、设置窗口。
/// 采样在后台队列（Scheduler 内部），渲染与状态变更全部回主线程。
final class AppCoordinator: NSObject, NSPopoverDelegate {
    private let settings = AppSettings()
    private let store = MetricStore()
    private let samplers = SamplerSet()
    private let scheduler = Scheduler()

    private var controllers: [ModuleID: StatusItemController] = [:]
    private var mergedController: StatusItemController?
    private let popover = NSPopover()
    private var settingsWindowController: SettingsWindowController?
    private var cancellables: Set<AnyCancellable> = []
    private var lastSnapshot = SystemSnapshot()

    /// NSStatusItem 后创建的排在左侧，倒序创建让默认顺序为 CPU · MEM · 网络 · 磁盘。
    private static let creationOrder: [ModuleID] = [.disk, .network, .memory, .cpu]

    func start() {
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        rebuildStatusItems()
        bindSettings()
        observeScreenSleep()
        restartScheduler()
    }

    // MARK: - 采样循环

    private func restartScheduler() {
        let enabled = settings.enabledModules
        scheduler.handler = { [weak self] in
            guard let self else { return }
            let snapshot = self.samplers.sample(enabled: enabled)
            DispatchQueue.main.async { self.apply(snapshot) }
        }
        scheduler.start(interval: settings.refreshInterval)
    }

    private func apply(_ snapshot: SystemSnapshot) {
        store.apply(snapshot)
        lastSnapshot = snapshot
        renderAll()
    }

    private func renderAll() {
        let style = settings.statusStyle
        let labelStyle = settings.labelStyle

        if let merged = mergedController {
            let modules = ModuleID.allCases.filter(settings.enabledModules.contains)
            // 仅迷你图样式需要历史数据，其余模式不做无谓的数组拷贝
            var histories: [ModuleID: [Double]] = [:]
            if style == .graph {
                histories[.cpu] = store.history(.cpuTotal)
                histories[.memory] = store.history(.memoryUsedFraction)
            }
            merged.update(StatusRenderer.renderMerged(
                modules: modules,
                snapshot: lastSnapshot,
                style: style,
                labelStyle: labelStyle,
                histories: histories
            ))
            return
        }

        for (module, controller) in controllers {
            let history: [Double]
            if style == .graph {
                switch module {
                case .cpu: history = store.history(.cpuTotal)
                case .memory: history = store.history(.memoryUsedFraction)
                default: history = []
                }
            } else {
                history = []
            }
            let output = StatusRenderer.render(
                module: module,
                snapshot: lastSnapshot,
                style: style,
                labelStyle: labelStyle,
                history: history
            )
            controller.update(output)
        }
    }

    // MARK: - 状态栏 item 管理

    private func rebuildStatusItems() {
        if settings.mergeModules {
            for (_, controller) in controllers { controller.remove() }
            controllers = [:]
            if mergedController == nil {
                mergedController = makeController(autosaveName: "statly.merged", toolTip: "Statly")
            }
        } else {
            mergedController?.remove()
            mergedController = nil
            let enabled = settings.enabledModules
            for (module, controller) in controllers where !enabled.contains(module) {
                controller.remove()
                controllers[module] = nil
            }
            for module in Self.creationOrder where enabled.contains(module) && controllers[module] == nil {
                controllers[module] = makeController(
                    autosaveName: "statly.\(module.rawValue)",
                    toolTip: "Statly · \(module.displayName)"
                )
            }
        }
    }

    private func makeController(autosaveName: String, toolTip: String) -> StatusItemController {
        let controller = StatusItemController(autosaveName: autosaveName, toolTip: toolTip)
        controller.onLeftClick = { [weak self] button in
            self?.togglePopover(from: button)
        }
        controller.onRightClick = { [weak self, weak controller] in
            guard let controller else { return }
            self?.showMenu(on: controller)
        }
        return controller
    }

    // MARK: - 设置联动

    private func bindSettings() {
        // @Published 在 willSet 阶段发事件，async 到下一个 runloop 再读属性拿到的才是新值。
        settings.$refreshInterval.dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.restartScheduler() }
            }
            .store(in: &cancellables)

        settings.$enabledModules.dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.rebuildStatusItems()
                    self.restartScheduler()
                    self.renderAll()
                }
            }
            .store(in: &cancellables)

        settings.$statusStyle.dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.renderAll() }
            }
            .store(in: &cancellables)

        settings.$labelStyle.dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.renderAll() }
            }
            .store(in: &cancellables)

        settings.$mergeModules.dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.rebuildStatusItems()
                    self.renderAll()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 睡眠/唤醒（轻量化守则：看不见就停）

    private func observeScreenSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc private func screensDidSleep() {
        scheduler.stop()
    }

    @objc private func screensDidWake() {
        // 在采样队列上重置基线，与后续 tick 串行，避免唤醒后首个周期出现速率尖峰。
        scheduler.perform { [samplers] in samplers.resetBaselines() }
        restartScheduler()
    }

    // MARK: - 弹窗

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        let view = PopoverView(
            store: store,
            settings: settings,
            onOpenSettings: { [weak self] in
                self?.popover.performClose(nil)
                self?.openSettings()
            },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        popover.contentViewController = NSHostingController(rootView: view)
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        // 轻量化守则：关闭即释放 SwiftUI 层
        popover.contentViewController = nil
    }

    // MARK: - 菜单与设置窗口

    private func showMenu(on controller: StatusItemController) {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "关于 Statly", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Statly", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        controller.showMenu(menu)
    }

    private func openSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(settings: settings)
            if let window = controller.window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(settingsWindowWillClose(_:)),
                    name: NSWindow.willCloseNotification,
                    object: window
                )
            }
            settingsWindowController = controller
        }
        settingsWindowController?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func settingsWindowWillClose(_ notification: Notification) {
        // 轻量化守则：设置窗口关闭即释放
        guard let window = settingsWindowController?.window,
              (notification.object as? NSWindow) === window else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        settingsWindowController = nil
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
