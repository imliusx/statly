import Foundation
import Combine

public enum HistoryKey: Hashable, CaseIterable {
    case cpuTotal
    case memoryUsedFraction
    case temperature
    case networkRx
    case networkTx
    case diskRead
    case diskWrite
}

/// 主线程持有的指标仓库：最新快照 + 每指标定长历史。
/// 弹窗（SwiftUI）观察它；状态栏渲染由 AppCoordinator 直接驱动。
public final class MetricStore: ObservableObject {
    @Published public private(set) var latest = SystemSnapshot()
    /// 本机可用的温度来源，启动时由协调器写入
    @Published public var availableTemperatureSources: Set<TemperatureSource> = []

    private var buffers: [HistoryKey: RingBuffer] = [:]
    private let historyCapacity: Int

    public init(historyCapacity: Int = 120) {
        self.historyCapacity = historyCapacity
    }

    public func apply(_ snapshot: SystemSnapshot) {
        if let cpu = snapshot.cpu { push(.cpuTotal, cpu.totalUsage) }
        if let memory = snapshot.memory { push(.memoryUsedFraction, memory.usedFraction) }
        if let temperature = snapshot.temperature { push(.temperature, temperature.celsius) }
        if let network = snapshot.network {
            push(.networkRx, network.rxPerSecond)
            push(.networkTx, network.txPerSecond)
        }
        if let disk = snapshot.disk {
            push(.diskRead, disk.readPerSecond)
            push(.diskWrite, disk.writePerSecond)
        }
        latest = snapshot
    }

    /// 清空某项历史。切换温度来源时用：两种来源量的不是同一件事，曲线不能混在一起。
    public func clearHistory(_ key: HistoryKey) {
        buffers[key] = nil
        objectWillChange.send()
    }

    public func history(_ key: HistoryKey) -> [Double] {
        buffers[key]?.values() ?? []
    }

    private func push(_ key: HistoryKey, _ value: Double) {
        buffers[key, default: RingBuffer(capacity: historyCapacity)].push(value)
    }
}
