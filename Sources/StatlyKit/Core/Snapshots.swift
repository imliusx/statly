import Foundation

public struct CPUSnapshot: Sendable {
    /// 0...1
    public let totalUsage: Double
    public let userUsage: Double
    public let systemUsage: Double
    public let perCore: [Double]

    public init(totalUsage: Double, userUsage: Double, systemUsage: Double, perCore: [Double]) {
        self.totalUsage = totalUsage
        self.userUsage = userUsage
        self.systemUsage = systemUsage
        self.perCore = perCore
    }
}

public enum MemoryPressure: Sendable {
    case normal
    case warning
    case critical

    public var displayName: String {
        switch self {
        case .normal: return "正常"
        case .warning: return "偏高"
        case .critical: return "严重"
        }
    }
}

public struct MemorySnapshot: Sendable {
    public let total: UInt64
    public let used: UInt64
    /// App 内存（internal - purgeable），口径对齐活动监视器
    public let app: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let pressure: MemoryPressure

    public var usedFraction: Double {
        total == 0 ? 0 : Double(used) / Double(total)
    }

    public init(total: UInt64, used: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, pressure: MemoryPressure) {
        self.total = total
        self.used = used
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.pressure = pressure
    }
}

public struct NetworkSnapshot: Sendable {
    /// bytes/s
    public let rxPerSecond: Double
    public let txPerSecond: Double

    public init(rxPerSecond: Double, txPerSecond: Double) {
        self.rxPerSecond = rxPerSecond
        self.txPerSecond = txPerSecond
    }
}

public struct DiskSnapshot: Sendable {
    public let totalCapacity: UInt64
    public let freeCapacity: UInt64
    /// bytes/s
    public let readPerSecond: Double
    public let writePerSecond: Double

    public var usedFraction: Double {
        totalCapacity == 0 ? 0 : Double(totalCapacity - freeCapacity) / Double(totalCapacity)
    }

    public init(totalCapacity: UInt64, freeCapacity: UInt64, readPerSecond: Double, writePerSecond: Double) {
        self.totalCapacity = totalCapacity
        self.freeCapacity = freeCapacity
        self.readPerSecond = readPerSecond
        self.writePerSecond = writePerSecond
    }
}

/// 温度档位。阈值按绝对温度划分：Apple Silicon 空载约 35–45°C，
/// 满载约 70–90°C，接近 100°C 开始降频。
public enum TemperatureLevel: Sendable {
    case low
    case medium
    case high

    public init(celsius: Double) {
        switch celsius {
        case ..<50: self = .low
        case ..<80: self = .medium
        default: self = .high
        }
    }

    /// 对应的 SF Symbol，水银柱高度随档位变化
    public var symbolName: String {
        switch self {
        case .low: return "thermometer.low"
        case .medium: return "thermometer.medium"
        case .high: return "thermometer.high"
        }
    }
}

public struct TemperatureSnapshot: Sendable {
    /// 读数来自哪个部件
    public let source: TemperatureSource
    /// 该来源的最高温度（摄氏度）
    public let celsius: Double
    /// 采样传感器的平均温度
    public let average: Double
    public let sensorCount: Int

    /// 映射到 0...1，供状态栏圆环使用。与其他模块的圆环口径一致：读数直接当百分比，
    /// 30°C 填 30%、90°C 填 90%、100°C 及以上填满。不设温度下限，
    /// 否则常见温区（30–45°C）会几乎看不出填充。
    public var heatFraction: Double {
        min(max(celsius / 100, 0), 1)
    }

    /// 冷热档位，供状态栏温度计图标选择水银柱高度。
    public var level: TemperatureLevel { TemperatureLevel(celsius: celsius) }

    public init(source: TemperatureSource = .cpu, celsius: Double, average: Double, sensorCount: Int) {
        self.source = source
        self.celsius = celsius
        self.average = average
        self.sensorCount = sensorCount
    }
}

// MARK: - 网络环境信息
//
// 以下类型**不属于** SystemSnapshot：那是常驻采样每个周期的产物，而这些是慢变量，
// 只在网络详情面板打开期间采集（轻量化守则"按需分级"，同 TopProcessStore）。

/// 本机网络环境。全部取自免权限的用户态 API。
public struct NetworkInfo: Sendable, Equatable {
    /// 主接口名，如 en0
    public var interfaceName: String?
    public var ipv4: String?
    /// 已排除 fe80:: 链路本地地址
    public var ipv6: String?
    public var router: String?
    public var dns: [String]

    public init(
        interfaceName: String? = nil,
        ipv4: String? = nil,
        ipv6: String? = nil,
        router: String? = nil,
        dns: [String] = []
    ) {
        self.interfaceName = interfaceName
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.router = router
        self.dns = dns
    }

    /// 公网 IP 的缓存键：本地网络环境没变就没必要重新查。
    /// 换 Wi-Fi、插拔网线、连 VPN 都会改变其中之一。
    public var fingerprint: String {
        "\(ipv4 ?? "-")|\(router ?? "-")"
    }
}

/// 公网 IP 查询结果。
public struct PublicIP: Sendable, Equatable {
    public let address: String
    public let city: String?
    public let region: String?
    public let country: String?
    /// 运营商（ipinfo 的 org 字段，形如 "AS4134 Chinanet"）
    public let org: String?

    public init(address: String, city: String? = nil, region: String? = nil, country: String? = nil, org: String? = nil) {
        self.address = address
        self.city = city
        self.region = region
        self.country = country
        self.org = org
    }

    /// "上海 · Chinanet"，两项都没有则为 nil。
    public var location: String? {
        let parts = [city, org].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// 公网 IP 的查询状态。disabled 表示用户在设置里关掉了该功能。
public enum PublicIPState: Sendable, Equatable {
    case disabled
    case idle
    case loading
    case loaded(PublicIP)
    case failed(String)
}

/// 一次采样周期产出的完整快照。未启用或首次采样无差值的模块为 nil。
public struct SystemSnapshot: Sendable {
    public var cpu: CPUSnapshot?
    public var memory: MemorySnapshot?
    public var temperature: TemperatureSnapshot?
    public var network: NetworkSnapshot?
    public var disk: DiskSnapshot?

    public init(
        cpu: CPUSnapshot? = nil,
        memory: MemorySnapshot? = nil,
        temperature: TemperatureSnapshot? = nil,
        network: NetworkSnapshot? = nil,
        disk: DiskSnapshot? = nil
    ) {
        self.cpu = cpu
        self.memory = memory
        self.temperature = temperature
        self.network = network
        self.disk = disk
    }
}
