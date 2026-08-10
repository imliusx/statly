import Foundation
import Combine
import ServiceManagement

/// 应用设置，UserDefaults 持久化。卸载残留 = 仅此一个 plist。
public final class AppSettings: ObservableObject {
    public static let allowedIntervals: [TimeInterval] = [1, 2, 5]

    /// 配置结构版本，用于新增模块等迁移
    private static let schemaVersion = 2

    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let enabledModules = "enabledModules"
        static let statusStyle = "statusStyle"
        static let labelStyle = "labelStyle"
        static let temperatureSource = "temperatureSource"
        static let showPublicIP = "showPublicIP"
        static let maskSensitiveInfo = "maskSensitiveInfo"
        static let schemaVersion = "schemaVersion"
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

    /// 温度模块显示哪个部件的温度，默认 CPU。
    @Published public var temperatureSource: TemperatureSource {
        didSet { defaults.set(temperatureSource.rawValue, forKey: Key.temperatureSource) }
    }

    /// 全局统一的标签样式，默认图标。
    @Published public var labelStyle: LabelStyle {
        didSet { defaults.set(labelStyle.rawValue, forKey: Key.labelStyle) }
    }

    /// 网络详情面板是否显示公网 IP，默认开启。
    /// 这是全 app 除"检查更新"外唯一的对外请求，关掉后一个字节都不发。
    @Published public var showPublicIP: Bool {
        didSet { defaults.set(showPublicIP, forKey: Key.showPublicIP) }
    }

    /// 是否遮住网络面板里能定位到个人的字段（公网 IP、归属地、全球 IPv6）。
    /// 由面板页脚的锁按钮切换；持久化保存，方便经常录屏、共享屏幕的人一直开着。
    @Published public var maskSensitiveInfo: Bool {
        didSet { defaults.set(maskSensitiveInfo, forKey: Key.maskSensitiveInfo) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedInterval = defaults.double(forKey: Key.refreshInterval)
        self.refreshInterval = Self.allowedIntervals.contains(storedInterval) ? storedInterval : 2

        if let raw = defaults.stringArray(forKey: Key.enabledModules) {
            var modules = Set(raw.compactMap(ModuleID.init(rawValue:)))
            // 迁移到 v2：温度模块是后加的，老配置里没有它，为已有用户默认开启，
            // 否则新功能会一直藏在设置里不出现
            if defaults.integer(forKey: Key.schemaVersion) < 2 {
                modules.insert(.temperature)
            }
            self.enabledModules = modules.isEmpty ? Set(ModuleID.allCases) : modules
        } else {
            self.enabledModules = Set(ModuleID.allCases)
        }
        defaults.set(Self.schemaVersion, forKey: Key.schemaVersion)

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
        if let raw = defaults.string(forKey: Key.temperatureSource),
           let source = TemperatureSource(rawValue: raw) {
            self.temperatureSource = source
        } else {
            self.temperatureSource = .cpu
        }
        // 默认开启：必须查 object(forKey:) 而不是 bool(forKey:)，
        // 后者在键不存在时返回 false，会让默认值永远生效不了
        self.showPublicIP = defaults.object(forKey: Key.showPublicIP) as? Bool ?? true
        // 默认不遮：打开面板通常就是为了看这些值
        self.maskSensitiveInfo = defaults.bool(forKey: Key.maskSensitiveInfo)
        // 清理早期版本遗留的设置键
        defaults.removeObject(forKey: "cpuStyle")
        defaults.removeObject(forKey: "mergeModules")
    }

    // MARK: - 开机自启（需要以 .app bundle 运行，裸二进制开发模式下不可用）

    public var canToggleLaunchAtLogin: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    public var launchAtLogin: Bool {
        get {
            // 非 .app 运行（开发用裸二进制、单元测试）时不去碰 SMAppService
            guard canToggleLaunchAtLogin else { return false }
            return SMAppService.mainApp.status == .enabled
        }
        set {
            guard canToggleLaunchAtLogin else { return }
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
