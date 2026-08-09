import Foundation
import Combine
import ServiceManagement

/// 应用设置，UserDefaults 持久化。卸载残留 = 仅此一个 plist。
public final class AppSettings: ObservableObject {
    public static let allowedIntervals: [TimeInterval] = [1, 2, 5]

    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let enabledModules = "enabledModules"
        static let statusStyle = "statusStyle"
        static let labelStyle = "labelStyle"
        static let mergeModules = "mergeModules"
    }

    private let defaults: UserDefaults

    @Published public var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    @Published public var enabledModules: Set<ModuleID> {
        didSet { defaults.set(enabledModules.map(\.rawValue).sorted(), forKey: Key.enabledModules) }
    }

    /// 全局统一的状态栏样式，默认圆环。
    @Published public var statusStyle: StatusStyle {
        didSet { defaults.set(statusStyle.rawValue, forKey: Key.statusStyle) }
    }

    /// 全局统一的标签样式，默认图标。
    @Published public var labelStyle: LabelStyle {
        didSet { defaults.set(labelStyle.rawValue, forKey: Key.labelStyle) }
    }

    /// 合并紧凑模式：所有模块拼进一个状态栏图标，模块间距由 Statly 控制。
    /// 关闭后每个模块是独立图标（可 ⌘ 拖动单独排序，但受系统项间距影响）。
    @Published public var mergeModules: Bool {
        didSet { defaults.set(mergeModules, forKey: Key.mergeModules) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedInterval = defaults.double(forKey: Key.refreshInterval)
        self.refreshInterval = Self.allowedIntervals.contains(storedInterval) ? storedInterval : 2

        if let raw = defaults.stringArray(forKey: Key.enabledModules) {
            let modules = Set(raw.compactMap(ModuleID.init(rawValue:)))
            self.enabledModules = modules.isEmpty ? Set(ModuleID.allCases) : modules
        } else {
            self.enabledModules = Set(ModuleID.allCases)
        }

        if let raw = defaults.string(forKey: Key.statusStyle), let style = StatusStyle(rawValue: raw) {
            self.statusStyle = style
        } else {
            self.statusStyle = .ring
        }
        if let raw = defaults.string(forKey: Key.labelStyle), let style = LabelStyle(rawValue: raw) {
            self.labelStyle = style
        } else {
            self.labelStyle = .icon
        }
        if defaults.object(forKey: Key.mergeModules) == nil {
            self.mergeModules = true
        } else {
            self.mergeModules = defaults.bool(forKey: Key.mergeModules)
        }
        // 清理早期版本遗留的 per-module 样式键
        defaults.removeObject(forKey: "cpuStyle")
    }

    // MARK: - 开机自启（需要以 .app bundle 运行，裸二进制开发模式下不可用）

    public var canToggleLaunchAtLogin: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    public var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Statly: launch-at-login toggle failed: \(error)")
            }
        }
    }
}
