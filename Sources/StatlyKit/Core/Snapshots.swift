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

public struct TemperatureSnapshot: Sendable {
    /// 最高晶粒温度（摄氏度）
    public let celsius: Double
    /// 采样传感器的平均温度
    public let average: Double
    public let sensorCount: Int

    /// 映射到 0...1，供状态栏圆环使用。30°C 以下算凉，100°C 视为满。
    public var heatFraction: Double {
        min(max((celsius - 30) / 70, 0), 1)
    }

    public init(celsius: Double, average: Double, sensorCount: Int) {
        self.celsius = celsius
        self.average = average
        self.sensorCount = sensorCount
    }
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
